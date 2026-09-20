import os
import hashlib
import logging
import tempfile
import cv2
import numpy as np
from PIL import Image, ImageStat, ImageOps
from django.conf import settings
from django.utils import timezone
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

                    # Dark lighting check (PIL)
                    stat = ImageStat.Stat(img.convert('L'))
                    mean_brightness = stat.mean[0]
                    if mean_brightness < 35:
                        warnings.append(f"Lighting is too dark in {os.path.basename(path)}.")

                    # Contrast check (blurriness indicator)
                    std_dev = stat.stddev[0]
                    if std_dev < 10:
                        warnings.append(f"Image {os.path.basename(path)} might be too blurry or low contrast.")

                # OpenCV blur detection via Laplacian variance
                try:
                    cv_img = cv2.imread(path)
                    if cv_img is not None:
                        gray = cv2.cvtColor(cv_img, cv2.COLOR_BGR2GRAY)
                        variance = cv2.Laplacian(gray, cv2.CV_64F).var()
                        blur_threshold = getattr(settings, 'AI_BLUR_VARIANCE_THRESHOLD', 100.0)
                        if variance < blur_threshold:
                            warnings.append(
                                f"Image {os.path.basename(path)} might be blurry or out of focus (Laplacian variance: {variance:.1f})."
                            )
                except Exception as cv_e:
                    logger.warning(f"OpenCV blur detection failed on {os.path.basename(path)}: {cv_e}")

                unique_paths.append(path)

            except Exception as e:
                errors.append(f"Image {os.path.basename(path)} is corrupted or unreadable: {e}")

        return errors, warnings, unique_paths

    def _preprocess_image_for_ai(self, image_path: str, is_dark: bool) -> tuple:
        """
        Auto-orients (EXIF) and applies light contrast/brightness normalization (CLAHE)
        ONLY if the image was flagged as too dark.
        Saves modified image to a new temp file so raw user upload is never overwritten.
        Returns: (file_path_to_use, is_temporary)
        """
        needs_temp = False
        try:
            with Image.open(image_path) as pil_img:
                # 1. EXIF orientation correction
                transposed = ImageOps.exif_transpose(pil_img)
                if transposed is not pil_img:
                    needs_temp = True
                else:
                    transposed = pil_img.copy()

                # 2. Contrast/brightness normalization ONLY if flagged as too dark
                if is_dark:
                    needs_temp = True
                    np_rgb = np.array(transposed.convert('RGB'))
                    lab = cv2.cvtColor(np_rgb, cv2.COLOR_RGB2LAB)
                    l_chan, a_chan, b_chan = cv2.split(lab)
                    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
                    l_enhanced = clahe.apply(l_chan)
                    enhanced_lab = cv2.merge([l_enhanced, a_chan, b_chan])
                    enhanced_rgb = cv2.cvtColor(enhanced_lab, cv2.COLOR_LAB2RGB)
                    transposed = Image.fromarray(enhanced_rgb)

                if needs_temp:
                    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg', prefix='freshtrack_prep_')
                    transposed.convert('RGB').save(tmp.name, format='JPEG', quality=95)
                    tmp.close()
                    return tmp.name, True

        except Exception as e:
            logger.warning(f"Image preprocessing failed for {image_path}: {e}")

        return image_path, False

    def process_scan(self, image_paths: list) -> dict:
        """
        Executes the two-stage pipeline:
        1. Validates image qualities (corruption, resolution, darkness, OpenCV Laplacian blur).
        2. Preprocesses valid images (EXIF auto-orientation, CLAHE darkness normalization on temp copy).
        3. Performs Google Cloud Vision OCR if enabled.
        4. Invokes Gemini Client combining visual and OCR contexts.
        """
        # 1. Run quality validations
        errors, warnings, valid_paths = self.run_image_quality_checks(image_paths)
        if errors:
            logger.error(f"Image validation failed: {errors}")
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
        dark_warning_filenames = {
            os.path.basename(path) for path in valid_paths 
            if any(f"Lighting is too dark in {os.path.basename(path)}" in w for w in warnings)
        }

        prepared_paths = []
        temp_files_to_cleanup = []

        for path in valid_paths:
            is_dark = os.path.basename(path) in dark_warning_filenames
            prep_path, is_temp = self._preprocess_image_for_ai(path, is_dark=is_dark)
            prepared_paths.append(prep_path)
            if is_temp:
                temp_files_to_cleanup.append(prep_path)

        try:
            # 3. OCR Text Extraction Stage
            ocr_text = ""
            ocr_dates = {}
            ocr_enabled = getattr(settings, 'OCR_ENABLED', True)
            
            if ocr_enabled:
                ocr_results = []
                for path in prepared_paths:
                    res = self.ocr_client.extract_text(path)
                    if res.get("success") and res.get("text"):
                        ocr_results.append(res["text"])
                
                if ocr_results:
                    ocr_text = "\n---\n".join(ocr_results)
                    # Parse expiry dates from OCR text directly
                    ocr_dates = OCRDateParser.extract_dates(ocr_text)
                    logger.info(f"OCR parsed packaging dates: {ocr_dates}")

            # 4. Gemini Multimodal Analysis Stage
            ai_result = self.ai_client.analyze_grocery_images(prepared_paths, ocr_context=ocr_text)
            items = ai_result.get("items", [])
            
            # 5. Accuracy Alignment: Resolve date conflicts & append warnings
            for item in items:
                # Add validation warnings found during quality checks
                item["warnings"] = list(set(item.get("warnings", []) + warnings))

                # Date alignment logic
                if ocr_dates and ocr_dates.get("expiry_date"):
                    # Check if Gemini extracted a different date
                    gemini_exp = item.get("expiry_date")
                    ocr_exp = ocr_dates["expiry_date"].isoformat()
                    
                    if gemini_exp and gemini_exp != ocr_exp:
                        # Conflict! Mark as Low confidence and prompt user choice
                        item["date_confidence"] = "Low"
                        item["date_source"] = "ocr_verified"
                        item["raw_date_text"] = f"Conflict: Gemini found {gemini_exp} | OCR found {ocr_exp}"
                        item["warnings"].append("Conflicting packaging date values detected between OCR and AI.")
                    else:
                        # Align item dates with OCR parsed dates
                        item["expiry_date"] = ocr_exp
                        item["manufacturing_date"] = ocr_dates["manufacturing_date"].isoformat() if ocr_dates.get("manufacturing_date") else None
                        item["packed_date"] = ocr_dates["packed_date"].isoformat() if ocr_dates.get("packed_date") else None
                        item["best_before_date"] = ocr_dates["best_before_date"].isoformat() if ocr_dates.get("best_before_date") else None
                        item["date_type"] = ocr_dates.get("date_type", "unknown")
                        item["date_source"] = ocr_dates.get("date_source", "unknown")
                        item["date_confidence"] = ocr_dates.get("date_confidence", "Low")
                        item["raw_date_text"] = ocr_dates.get("raw_date_text", "")
                
                # Expiry bounds safety check and fallback shelf-life prediction
                if item.get("expiry_date"):
                    try:
                        exp = timezone.datetime.strptime(item["expiry_date"], "%Y-%m-%d").date()
                        if exp < timezone.now().date():
                            item["warnings"].append("Detected date has already expired.")
                    except ValueError:
                        item["expiry_date"] = None

                # Fallback to algorithmic shelf-life prediction if date is still missing
                if not item.get("expiry_date"):
                    try:
                        from apps.groceries.prediction_engine import ShelfLifePredictionEngine
                        prediction = ShelfLifePredictionEngine.predict({
                            'category': item.get('category', 'default'),
                            'storage_zone': item.get('storage_zone', 'pantry'),
                            'purchase_date': timezone.now().date(),
                        })
                        item["expiry_date"] = prediction['predicted_expiry'].isoformat()
                        item["date_type"] = "estimated"
                        item["date_source"] = "calculated_shelf_life"
                        if not item.get("storage_reason"):
                            item["storage_reason"] = prediction.get('storage_recommendation_why', '')
                        if not item.get("shelf_life_guidance"):
                            item["shelf_life_guidance"] = prediction.get('storage_recommendation_how', '')
                    except Exception as pred_err:
                        logger.warning(f"Shelf life prediction fallback failed: {pred_err}")
                        # Default 14 days
                        item["expiry_date"] = (timezone.now().date() + timezone.timedelta(days=14)).isoformat()
                        item["date_type"] = "estimated"
                        item["date_source"] = "calculated_shelf_life"

            return {
                "success": True,
                "items": items,
                "warnings": warnings
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
