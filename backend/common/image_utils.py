import os
import hashlib
from PIL import Image, ImageOps
from django.core.exceptions import ValidationError

# Protect against decompression bombs (max 25 Megapixels)
Image.MAX_IMAGE_PIXELS = 25_000_000

MAX_IMAGE_SIZE_BYTES = 5 * 1024 * 1024  # 5MB
MAX_DIMENSION = 8192  # 8192px maximum width or height
ALLOWED_IMAGE_FORMATS = {
    '.jpg': 'JPEG',
    '.jpeg': 'JPEG',
    '.png': 'PNG',
    '.webp': 'WEBP',
}

def validate_and_sanitize_image(image_file, max_size=MAX_IMAGE_SIZE_BYTES):
    """
    Validates file size, extension, real Pillow format, dimension limits,
    decompression bomb prevention, and returns True on success.
    Raises ValidationError on failure.
    """
    if image_file.size > max_size:
        raise ValidationError(f"File size exceeds limit of {max_size // (1024 * 1024)}MB.")

    ext = os.path.splitext(image_file.name)[1].lower()
    if ext not in ALLOWED_IMAGE_FORMATS:
        raise ValidationError(f"Unsupported file format '{ext}'. Allowed: {', '.join(ALLOWED_IMAGE_FORMATS.keys())}")

    try:
        image_file.seek(0)
        with Image.open(image_file) as img:
            img.verify()
            actual_format = img.format
            
        if actual_format != ALLOWED_IMAGE_FORMATS[ext]:
            raise ValidationError(f"Image extension '{ext}' does not match real format '{actual_format}'.")

        image_file.seek(0)
        with Image.open(image_file) as img:
            w, h = img.size
            if w > MAX_DIMENSION or h > MAX_DIMENSION:
                raise ValidationError(f"Image dimensions ({w}x{h}) exceed maximum allowed ({MAX_DIMENSION}x{MAX_DIMENSION}).")
    except ValidationError:
        raise
    except Exception as e:
        raise ValidationError(f"Invalid or corrupted image: {str(e)}")
    finally:
        image_file.seek(0)

    return True
