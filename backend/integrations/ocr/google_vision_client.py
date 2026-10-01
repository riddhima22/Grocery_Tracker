import io
import os
import json
import logging
from django.conf import settings
from google.cloud import vision
from google.oauth2 import service_account
from .base import OCRService

logger = logging.getLogger('freshtrack.ocr.google_vision')

class GoogleCloudVisionOCR(OCRService):
    def __init__(self):
        self.enabled = getattr(settings, 'OCR_ENABLED', True)
        self.client = None
        if not self.enabled:
            return

        # 1. Try initializing using GOOGLE_APPLICATION_CREDENTIALS_JSON (environment variable or Django setting)
        creds_json = getattr(settings, 'GOOGLE_APPLICATION_CREDENTIALS_JSON', None) or os.environ.get('GOOGLE_APPLICATION_CREDENTIALS_JSON')
        if creds_json and creds_json.strip():
            try:
                info = json.loads(creds_json)
                credentials = service_account.Credentials.from_service_account_info(info)
                self.client = vision.ImageAnnotatorClient(credentials=credentials)
                logger.info("Successfully initialized Google Cloud Vision client using GOOGLE_APPLICATION_CREDENTIALS_JSON.")
                return
            except Exception as e:
                logger.warning(f"Could not initialize Google Cloud Vision client from JSON credentials: {e}. Falling back to file path.")

        # 2. Fallback to GOOGLE_APPLICATION_CREDENTIALS file path for local development
        creds_file = getattr(settings, 'GOOGLE_APPLICATION_CREDENTIALS', None) or os.environ.get('GOOGLE_APPLICATION_CREDENTIALS')
        if creds_file and os.path.exists(creds_file):
            try:
                self.client = vision.ImageAnnotatorClient()
                logger.info("Successfully initialized Google Cloud Vision client using GOOGLE_APPLICATION_CREDENTIALS file path.")
                return
            except Exception as e:
                logger.warning(f"Could not initialize Google Cloud Vision client from file: {e}. OCR will be skipped.")
                self.enabled = False
                return

        logger.info("GOOGLE_APPLICATION_CREDENTIALS not configured or file not found. OCR skipped.")
        self.enabled = False

    def extract_text(self, image_path: str) -> dict:
        if not self.enabled or not self.client:
            logger.info("Google Cloud Vision OCR is disabled or not initialized.")
            return {"text": "", "blocks": [], "confidence": 0.0, "success": False}

        try:
            logger.info(f"Running Google Cloud Vision OCR on image: {image_path}")
            with io.open(image_path, 'rb') as image_file:
                content = image_file.read()

            image = vision.Image(content=content)
            
            # Use DOCUMENT_TEXT_DETECTION if configured, else standard TEXT_DETECTION
            provider_mode = getattr(settings, 'OCR_PROVIDER', 'TEXT_DETECTION')
            if provider_mode == 'DOCUMENT_TEXT_DETECTION':
                response = self.client.document_text_detection(image=image)
            else:
                response = self.client.text_detection(image=image)

            texts = response.text_annotations
            if not texts:
                logger.info("No text detected in image.")
                return {"text": "", "blocks": [], "confidence": 1.0, "success": True}

            full_text = texts[0].description
            blocks = []
            
            # The first annotation contains the entire text, subsequent ones are individual words/blocks
            for annotation in texts[1:]:
                blocks.append({
                    "text": annotation.description,
                    "confidence": getattr(annotation, 'confidence', 1.0)
                })

            if response.error.message:
                raise Exception(f"Google Cloud Vision API Error: {response.error.message}")

            logger.info(f"Google Cloud Vision OCR successfully extracted {len(blocks)} blocks.")
            return {
                "text": full_text,
                "blocks": blocks,
                "confidence": 1.0,
                "success": True
            }

        except Exception as e:
            logger.error(f"Google Cloud Vision OCR extraction failed: {e}", exc_info=True)
            return {
                "text": "",
                "blocks": [],
                "confidence": 0.0,
                "success": False,
                "error": str(e)
            }

    def object_localization(self, image_path: str) -> list:
        """
        Performs object localization (object detection) using Google Cloud Vision.
        Returns a list of dicts: [{"name": str, "score": float}, ...]
        Shares the same initialized vision.ImageAnnotatorClient.
        """
        if not self.enabled or not self.client:
            logger.info("Google Cloud Vision object localization is disabled or not initialized.")
            return []

        try:
            logger.info(f"Running Google Cloud Vision object localization on image: {image_path}")
            with io.open(image_path, 'rb') as image_file:
                content = image_file.read()

            image = vision.Image(content=content)
            response = self.client.object_localization(image=image)

            if response.error.message:
                raise Exception(f"Google Cloud Vision API Error: {response.error.message}")

            objects = []
            for annotation in response.localized_object_annotations:
                objects.append({
                    "name": annotation.name,
                    "score": getattr(annotation, 'score', 1.0)
                })

            logger.info(f"Google Cloud Vision object localization found {len(objects)} objects.")
            return objects

        except Exception as e:
            logger.error(f"Google Cloud Vision object localization failed: {e}", exc_info=True)
            return []

