class OCRService:
    def extract_text(self, image_path: str) -> dict:
        """
        Extracts visible text blocks from the image.
        Returns a dict:
        {
            "text": "Full concatenated text",
            "blocks": [
                {
                    "text": "block text",
                    "confidence": 0.95
                }
            ],
            "confidence": 0.92
        }
        """
        raise NotImplementedError("OCRService subclasses must implement extract_text")
