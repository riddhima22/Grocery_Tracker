import hashlib
import logging
import os
import tempfile
import time

import cv2
import numpy as np
from django.conf import settings
from django.utils import timezone
from PIL import Image, ImageOps, ImageStat

from integrations.ocr.google_vision_client import GoogleCloudVisionOCR
from integrations.ocr.text_parser import OCRDateParser

from .ai_service import AIService
from .gemini_client import AIContentBlockedError

logger = logging.getLogger('freshtrack.ai.model_router')

class ModelRouter:
    def __init__(self):
        self.ocr_client = GoogleCloudVisionOCR()
        self.ai_client = AIService()

    def run_image_quality_checks(self, image_paths: list) -> tuple:
        """
        Validates images for corruption, resolution, duplicate hashes, low lighting, and blur.
        Returns: (list_of_errors, list_of_warnings, list_of_unique_paths)
        """
        errors = []
        warnings = []
        seen_hashes = set()
        unique_paths = []

        max_size = getattr(settings, 'AI_MAX_IMAGE_SIZE_BYTES', 5 * 1024 * 1024) # 5MB

        for path in image_paths:
            if not os.path.exists(path):
                errors.append(f"Image file does not exist: {os.path.basename(path)}")
                continue

            # Size check
            size = os.path.getsize(path)
            if size > max_size:
                errors.append(f"Image {os.path.basename(path)} exceeds size limit.")
                continue

            # Duplicate hash check
            try:
                hasher = hashlib.md5()
                with open(path, 'rb') as f:
                    buf = f.read()
                hasher.update(buf)
                img_hash = hasher.hexdigest()

                if img_hash in seen_hashes:
                    warnings.append(f"Duplicate image detected: {os.path.basename(path)}")
                    continue
                seen_hashes.add(img_hash)
            except Exception as e:
                errors.append(f"Failed to check duplicate hash for {os.path.basename(path)}: {e}")
                continue

            # Open image and check dimensions/quality with PIL
            try:
                with Image.open(path) as img:
                    width, height = img.size

                    # Low resolution check
                    if width < 150 or height < 150:
                        errors.append(f"Image {os.path.basename(path)} resolution is too low ({width}x{height}).")
                        continue

                    # In-memory thumbnail for rapid blur and quality detection without full-res overhead
                    try:
                        thumb = img.copy()
                        thumb.thumbnail((512, 512), resample=Image.Resampling.BILINEAR)
                        gray_thumb = thumb.convert('L')
                        stat = ImageStat.Stat(gray_thumb)
                        mean_brightness = stat.mean[0]
                        if mean_brightness < 35:
                            warnings.append(f"Lighting is too dark in {os.path.basename(path)}.")

                        std_dev = stat.stddev[0]
                        if std_dev < 10:
                            warnings.append(f"Image {os.path.basename(path)} might be too blurry or low contrast.")

                        gray_arr = np.array(gray_thumb)
                        variance = cv2.Laplacian(gray_arr, cv2.CV_64F).var()
                        blur_threshold = getattr(settings, 'AI_BLUR_VARIANCE_THRESHOLD', 100.0)
                        if variance < blur_threshold:
                            warnings.append(
                                f"Image {os.path.basename(path)} might be blurry or out of focus (Laplacian variance: {variance:.1f})."
                            )
                    except Exception as cv_e:
                        logger.warning(f"Laplacian blur detection failed on {os.path.basename(path)}: {cv_e}")

                unique_paths.append(path)

            except Exception as e:
                errors.append(f"Image {os.path.basename(path)} is corrupted or unreadable: {e}")

        return errors, warnings, unique_paths

    def _save_temp_jpeg(self, img: Image.Image, quality: int = 82) -> str:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg', prefix='freshtrack_prep_')
        img.convert('RGB').save(tmp.name, format='JPEG', quality=quality)
        tmp.close()
        return tmp.name

    def _apply_dark_enhancement(self, img: Image.Image) -> Image.Image:
        np_rgb = np.array(img.convert('RGB'))
        lab = cv2.cvtColor(np_rgb, cv2.COLOR_RGB2LAB)
        l_chan, a_chan, b_chan = cv2.split(lab)
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        l_enhanced = clahe.apply(l_chan)
        enhanced_lab = cv2.merge([l_enhanced, a_chan, b_chan])
        enhanced_rgb = cv2.cvtColor(enhanced_lab, cv2.COLOR_LAB2RGB)
        return Image.fromarray(enhanced_rgb)

    def _prepare_image_and_crops_for_ai(self, image_path: str, is_dark: bool) -> list:
        """
        Preprocesses an image and generates intelligent high-res crops for large/crowded images:
        1. Auto-orients (EXIF).
        2. Produces a full-scene overview (scaled to max 1280px).
        3. For large images (longest side >= 1600px or area >= 1.8MP), extracts two overlapping
           high-detail crops (left/right for landscape, top/bottom for portrait) scaled to max 1280px,
           ensuring small packaging text and labels remain readable without blur.
        4. Applies CLAHE contrast enhancement if dark.
        Returns list of (temp_file_path, is_temp) tuples.
        """
        results = []
        try:
            with Image.open(image_path) as pil_img:
                transposed = ImageOps.exif_transpose(pil_img)
                if transposed is pil_img:
                    transposed = pil_img.copy()

                width, height = transposed.size
                longest = max(width, height)
                max_dim = getattr(settings, 'AI_MAX_IMAGE_DIMENSION', 1280)
                quality = getattr(settings, 'AI_IMAGE_QUALITY', 82)

                # 1. Full-scene overview
                overview = transposed.copy()
                if longest > max_dim:
                    scale = max_dim / float(longest)
                    new_w = max(150, int(round(width * scale)))
                    new_h = max(150, int(round(height * scale)))
                    overview = overview.resize((new_w, new_h), resample=Image.Resampling.BILINEAR)

                if is_dark:
                    overview = self._apply_dark_enhancement(overview)

                overview_tmp = self._save_temp_jpeg(overview, quality)
                results.append((overview_tmp, True))

                # 2. Large/high-res image tiling check
                # For images >= 1600px on the longest dimension or >= 1.8 megapixels, extract 2 overlapping crops
                tiling_enabled = getattr(settings, 'AI_TILING_ENABLED', True)
                if tiling_enabled and (longest >= 1600 or (width * height >= 1800000)):
                    crops = []
                    if width >= height:
                        # Landscape: Left crop (0-58%) & Right crop (42-100%)
                        left_box = (0, 0, int(round(width * 0.58)), height)
                        right_box = (int(round(width * 0.42)), 0, width, height)
                        crops.append(transposed.crop(left_box))
                        crops.append(transposed.crop(right_box))
                    else:
                        # Portrait: Top crop (0-58%) & Bottom crop (42-100%)
                        top_box = (0, 0, width, int(round(height * 0.58)))
                        bottom_box = (0, int(round(height * 0.42)), width, height)
                        crops.append(transposed.crop(top_box))
                        crops.append(transposed.crop(bottom_box))

                    for crop_img in crops:
                        c_w, c_h = crop_img.size
                        c_longest = max(c_w, c_h)
                        if c_longest > max_dim:
                            c_scale = max_dim / float(c_longest)
                            c_new_w = max(150, int(round(c_w * c_scale)))
                            c_new_h = max(150, int(round(c_h * c_scale)))
                            crop_img = crop_img.resize((c_new_w, c_new_h), resample=Image.Resampling.BILINEAR)

                        if is_dark:
                            crop_img = self._apply_dark_enhancement(crop_img)

                        crop_tmp = self._save_temp_jpeg(crop_img, quality)
                        results.append((crop_tmp, True))

                del transposed
                import gc
                gc.collect()
                return results

        except Exception as e:
            logger.warning(f"High-res preprocessing and crop generation failed for {image_path}: {e}")
            if results:
                return results
            return [(image_path, False)]

    def _preprocess_image_for_ai(self, image_path: str, is_dark: bool) -> tuple:
        """
        Preprocesses a single image for AI consumption:
        1. Auto-orients (EXIF).
        2. Downscales longest dimension to sensible max resolution (default 1280px) preserving label text.
        3. Applies light contrast/brightness normalization (CLAHE) if flagged as dark.
        4. Saves to temporary JPEG quality 82 for fast encoding and ~100-200 KB network payload.
        Always saves to a temporary file, keeping the raw uploaded image intact.
        Returns: (file_path_to_use, is_temporary)
        """
        try:
            with Image.open(image_path) as pil_img:
                transposed = ImageOps.exif_transpose(pil_img)
                if transposed is pil_img:
                    transposed = pil_img.copy()

                width, height = transposed.size
                longest = max(width, height)
                max_dim = getattr(settings, 'AI_MAX_IMAGE_DIMENSION', 1280)
                if longest > max_dim:
                    scale = max_dim / float(longest)
                    new_w = max(150, int(round(width * scale)))
                    new_h = max(150, int(round(height * scale)))
                    transposed = transposed.resize((new_w, new_h), resample=Image.Resampling.BILINEAR)

                if is_dark:
                    transposed = self._apply_dark_enhancement(transposed)

                tmp_name = self._save_temp_jpeg(transposed, getattr(settings, 'AI_IMAGE_QUALITY', 82))
                del transposed
                import gc
                gc.collect()
                return tmp_name, True

        except Exception as e:
            logger.warning(f"Image preprocessing failed for {image_path}: {e}")

        return image_path, False

    def process_scan(self, image_paths: list, correlation_id: str = None, session_id: str = None) -> dict:
        """
        Executes the two-stage pipeline:
        1. Validates image qualities (corruption, resolution, darkness, Laplacian blur).
        2. Preprocesses valid images (EXIF auto-orientation, CLAHE darkness normalization on temp copy).
        3. Performs Google Cloud Vision OCR if enabled.
        4. Invokes AI Client combining visual and OCR contexts.
        """
        t0 = time.time()
        corr_tag = f"CorrelationID={correlation_id} " if correlation_id else ""

        # 1. Run quality validations
        errors, warnings, valid_paths = self.run_image_quality_checks(image_paths)
        t_qc = time.time() - t0

        if errors:
            logger.error(f"[image_qc_failed] {corr_tag}Image validation failed: {errors}")
            return {
                "success": False,
                "error": errors[0],
                "warnings": warnings,
                "items": []
            }

        if not valid_paths:
            return {
                "success": False,
                "error": "No valid images found for processing.",
                "warnings": warnings,
                "items": []
            }

        # 2. Preprocess images for AI (EXIF auto-orientation, CLAHE for dark images)
        t_prep_start = time.time()
        dark_warning_filenames = {
            os.path.basename(path) for path in valid_paths
            if any(f"Lighting is too dark in {os.path.basename(path)}" in w for w in warnings)
        }

        prepared_paths = []
        temp_files_to_cleanup = []

        for path in valid_paths:
            is_dark = os.path.basename(path) in dark_warning_filenames
            prep_results = self._prepare_image_and_crops_for_ai(path, is_dark=is_dark)
            for prep_path, is_temp in prep_results:
                prepared_paths.append(prep_path)
                if is_temp:
                    temp_files_to_cleanup.append(prep_path)

        t_prep = time.time() - t_prep_start
        logger.info(
            f"[image_preprocessed] {corr_tag}session_id={session_id or 'unknown'} "
            f"input_images={len(valid_paths)} total_views_and_crops={len(prepared_paths)} elapsed_ms={int(t_prep * 1000)}"
        )

        try:
            # 3. OCR Text Extraction & Object Detection Stage
            t_ocr_start = time.time()
            ocr_text = ""
            ocr_context = ""
            ocr_dates = {}
            ocr_enabled = getattr(settings, 'OCR_ENABLED', True)

            if ocr_enabled:
                ocr_results = []
                detected_objects = []
                for path in prepared_paths:
                    res = self.ocr_client.extract_text(path)
                    if res.get("success") and res.get("text"):
                        ocr_results.append(res["text"])
                    if hasattr(self.ocr_client, 'object_localization'):
                        objs = self.ocr_client.object_localization(path)
                        if objs:
                            for o in objs:
                                name = o.get("name", "Item")
                                score = o.get("score", 1.0)
                                detected_objects.append(f"{name} (confidence: {score:.2f})")
                    import gc
                    gc.collect()

                context_sections = []
                if ocr_results:
                    ocr_text = "\n---\n".join(ocr_results)
                    context_sections.append(f"PACKAGING OCR TEXT BLOCKS:\n{ocr_text}")
                    # Parse expiry dates from OCR text directly
                    ocr_dates = OCRDateParser.extract_dates(ocr_text)
                    logger.info(f"OCR parsed packaging dates: {ocr_dates}")

                if detected_objects:
                    obj_hint_text = f"GOOGLE VISION OBJECT-DETECTION HINTS (DETECTED ITEMS COUNT: {len(detected_objects)}):\n" + "\n".join(f"- {d}" for d in detected_objects)
                    context_sections.append(obj_hint_text)
                    logger.info(f"Google Vision object localization detected {len(detected_objects)} objects.")

                ocr_context = "\n\n".join(context_sections) if context_sections else ""

            t_ocr = time.time() - t_ocr_start

            # 4. Multimodal AI Analysis Stage
            t_ai_start = time.time()
            ai_result = self.ai_client.analyze_grocery_images(
                prepared_paths,
                ocr_context=ocr_context,
                correlation_id=correlation_id
            )
            raw_items = ai_result.get("items", [])
            t_ai = time.time() - t_ai_start

            # 5. Candidate Deduplication across multi-region crops and overlapping tiles
            t_dedup_start = time.time()
            items = self.deduplicate_items(raw_items)
            t_dedup = time.time() - t_dedup_start

            # 6. Accuracy Alignment: Resolve date conflicts & append warnings
            t_align_start = time.time()
            items = self.align_item_dates(items, ocr_dates=ocr_dates, warnings=warnings)
            t_align = time.time() - t_align_start

            t_total = time.time() - t0
            logger.info(
                f"[model_router_completed] {corr_tag}pipeline completed in {t_total:.2f}s: "
                f"QC={t_qc:.2f}s, Prep={t_prep:.2f}s, OCR={t_ocr:.2f}s, AI={t_ai:.2f}s, Dedup={t_dedup:.2f}s, Align={t_align:.2f}s "
                f"(raw={len(raw_items)}, deduplicated={len(items)} items)."
            )

            return {
                "success": True,
                "items": items,
                "warnings": warnings,
                "timings": {
                    "quality_check_s": round(t_qc, 2),
                    "prep_s": round(t_prep, 2),
                    "ocr_s": round(t_ocr, 2),
                    "ai_s": round(t_ai, 2),
                    "dedup_s": round(t_dedup, 2),
                    "align_s": round(t_align, 2),
                    "total_s": round(t_total, 2),
                }
            }

        except AIContentBlockedError as e:
            logger.warning(f"Scan analysis content blocked: {e}")
            return {
                "success": False,
                "error": "The image couldn't be analyzed — try a clearer photo or a different angle.",
                "warnings": warnings,
                "items": []
            }
        except Exception as e:
            logger.error(f"Failed to route analysis: {e}", exc_info=True)
            return {
                "success": False,
                "error": f"AI service failed: {e}",
                "warnings": warnings,
                "items": []
            }
        finally:
            for tmp_path in temp_files_to_cleanup:
                try:
                    if os.path.exists(tmp_path):
                        os.remove(tmp_path)
                except Exception as ex:
                    logger.debug(f"Failed to remove temp file {tmp_path}: {ex}")

    def align_item_dates(self, items: list, ocr_dates: dict = None, warnings: list = None) -> list:
        """
        Enforces strict date semantics on detected items:
        1. Aligns with OCR parsed packaging dates and flags conflicts.
        2. IF printed date detected: expiry_date is set, is_expiry_estimated is False.
        3. IF NO printed date detected: expiry_date is None, is_expiry_estimated is True,
           and estimated_consumption_date is calculated from shelf life.
        """
        warnings = warnings or []
        ocr_dates = ocr_dates or {}

        for item in items:
            item["warnings"] = list(set(item.get("warnings", []) + warnings))

            # Date alignment logic with OCR
            if ocr_dates and ocr_dates.get("expiry_date"):
                gemini_exp = item.get("expiry_date")
                ocr_exp = ocr_dates["expiry_date"].isoformat()

                if gemini_exp and gemini_exp != ocr_exp:
                    item["date_confidence"] = "Low"
                    item["date_source"] = "ocr_verified"
                    item["raw_date_text"] = f"Conflict: Gemini found {gemini_exp} | OCR found {ocr_exp}"
                    item["warnings"].append("Conflicting packaging date values detected between OCR and AI.")
                else:
                    item["expiry_date"] = ocr_exp
                    item["manufacturing_date"] = ocr_dates["manufacturing_date"].isoformat() if ocr_dates.get("manufacturing_date") else None
                    item["packed_date"] = ocr_dates["packed_date"].isoformat() if ocr_dates.get("packed_date") else None
                    item["best_before_date"] = ocr_dates["best_before_date"].isoformat() if ocr_dates.get("best_before_date") else None
                    item["date_type"] = ocr_dates.get("date_type", "unknown")
                    item["date_source"] = ocr_dates.get("date_source", "unknown")
                    item["date_confidence"] = ocr_dates.get("date_confidence", "Low")
                    item["raw_date_text"] = ocr_dates.get("raw_date_text", "")

            # Expiry bounds safety check and shelf-life semantics enforcement
            has_printed_expiry = False
            if item.get("expiry_date"):
                try:
                    exp = None
                    d_str = str(item["expiry_date"]).strip()
                    for fmt in ('%Y-%m-%d', '%d/%m/%Y', '%d-%m-%Y', '%m/%d/%Y', '%Y/%m/%d'):
                        try:
                            exp = timezone.datetime.strptime(d_str[:10], fmt).date()
                            break
                        except (ValueError, TypeError):
                            pass
                    if exp:
                        item["expiry_date"] = exp.isoformat()
                        item["is_expiry_estimated"] = False
                        item["estimated_consumption_date"] = None
                        has_printed_expiry = True
                        if exp < timezone.now().date():
                            item["warnings"].append("Detected date has already expired.")
                    else:
                        item["expiry_date"] = None
                except Exception:
                    item["expiry_date"] = None

            # CRITICAL SEMANTIC RULE:
            # If NO printed expiry exists on package, expiry_date MUST remain None!
            # We calculate estimated_consumption_date separately and flag is_expiry_estimated = True.
            if not has_printed_expiry:
                item["expiry_date"] = None
                item["is_expiry_estimated"] = True
                item["date_type"] = "estimated"
                item["date_source"] = "calculated_shelf_life"
                try:
                    from apps.groceries.prediction_engine import (
                        ShelfLifePredictionEngine,
                    )
                    prediction = ShelfLifePredictionEngine.predict({
                        'category': item.get('category', 'default'),
                        'storage_zone': item.get('storage_zone', 'pantry'),
                        'purchase_date': timezone.now().date(),
                    })
                    item["estimated_consumption_date"] = prediction['predicted_expiry'].isoformat()
                    if not item.get("storage_reason"):
                        item["storage_reason"] = prediction.get('storage_recommendation_why', '')
                    if not item.get("shelf_life_guidance"):
                        item["shelf_life_guidance"] = prediction.get('storage_recommendation_how', '')
                except Exception as pred_err:
                    logger.warning(f"Shelf life prediction fallback failed: {pred_err}")
                    item["estimated_consumption_date"] = (timezone.now().date() + timezone.timedelta(days=14)).isoformat()
            else:
                item["estimated_consumption_date"] = None
                item["is_expiry_estimated"] = False

        return items

    @staticmethod
    def deduplicate_items(items: list) -> list:
        """
        Deduplicates candidate grocery items identified across multi-region crops,
        high-resolution tiles, or multiple views of the same scene.
        - Preserves all 23 grocery fields.
        - Merges identical products without inflating quantities: if the same physical item
          was detected in both overview and detail crops or overlapping tiles, quantity is set to max(q1, q2).
        - Keeps higher confidence and more complete metadata (printed expiry dates, verified brand, storage advice).
        - Distinguishes separate items even in the same category (e.g. Red Onions vs White Onions vs Garlic).
        """
        if not items:
            return []

        import re

        def normalize_key(item):
            name = str(item.get("name") or "").strip().lower()
            clean_name = re.sub(r'[^a-z0-9]', '', name)
            brand = re.sub(r'[^a-z0-9]', '', str(item.get("brand") or "").strip().lower())
            category = str(item.get("category") or "").strip().lower()
            unit = str(item.get("unit") or "").strip().lower()
            return clean_name, brand, category, unit

        confidence_rank = {"high": 3, "medium": 2, "low": 1}

        merged_items = []
        seen_map = {}

        for item in items:
            clean_name, brand, category, unit = normalize_key(item)
            if not clean_name:
                continue

            key = (clean_name, brand, category, unit)
            fallback_key = (clean_name, category) if not brand else None

            matched_idx = seen_map.get(key)
            if matched_idx is None and fallback_key:
                matched_idx = seen_map.get(fallback_key)

            if matched_idx is not None:
                target = merged_items[matched_idx]

                # 1. Quantity: take max(q1, q2) to prevent double counting across overlapping crops
                try:
                    q_existing = float(target.get("quantity") or 1.0)
                    q_new = float(item.get("quantity") or 1.0)
                    target["quantity"] = max(q_existing, q_new)
                except (ValueError, TypeError):
                    pass

                # 2. Confidence: retain higher confidence level
                c_existing = confidence_rank.get(str(target.get("confidence") or "").lower(), 1)
                c_new = confidence_rank.get(str(item.get("confidence") or "").lower(), 1)
                if c_new > c_existing:
                    target["confidence"] = item.get("confidence")

                # 3. Name & Brand & Description: keep more descriptive
                if len(str(item.get("name") or "")) > len(str(target.get("name") or "")):
                    target["name"] = item.get("name")
                if not target.get("brand") and item.get("brand"):
                    target["brand"] = item.get("brand")
                if not target.get("description") and item.get("description"):
                    target["description"] = item.get("description")

                # 4. Storage guidance
                if not target.get("storage_reason") and item.get("storage_reason"):
                    target["storage_reason"] = item.get("storage_reason")
                if not target.get("shelf_life_guidance") and item.get("shelf_life_guidance"):
                    target["shelf_life_guidance"] = item.get("shelf_life_guidance")

                # 5. Expiry Dates: prefer printed/verified over estimated/None
                if not target.get("expiry_date") and item.get("expiry_date"):
                    target["expiry_date"] = item.get("expiry_date")
                    target["is_expiry_estimated"] = item.get("is_expiry_estimated", False)
                    target["date_source"] = item.get("date_source")
                    target["raw_date_text"] = item.get("raw_date_text", "")
                    target["date_type"] = item.get("date_type")
                    target["date_confidence"] = item.get("date_confidence", "High")

                # 6. Warnings: merge without duplicate strings
                existing_warnings = set(target.get("warnings") or [])
                new_warnings = set(item.get("warnings") or [])
                target["warnings"] = list(existing_warnings.union(new_warnings))

            else:
                new_item = dict(item)
                if not isinstance(new_item.get("warnings"), list):
                    new_item["warnings"] = []
                idx = len(merged_items)
                merged_items.append(new_item)
                seen_map[key] = idx
                if fallback_key:
                    seen_map[fallback_key] = idx

        return merged_items

    def parse_grocery_response(self, json_data: dict, ocr_dates: dict = None, warnings: list = None) -> dict:
        """Parses, deduplicates, and aligns grocery items from a JSON dictionary."""
        items = json_data.get("items", [])
        deduped = self.deduplicate_items(items)
        aligned_items = self.align_item_dates(deduped, ocr_dates=ocr_dates, warnings=warnings)
        return {
            "success": True,
            "items": aligned_items,
            "warnings": warnings or []
        }

