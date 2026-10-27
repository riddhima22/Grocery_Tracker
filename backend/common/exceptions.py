from rest_framework import status
from rest_framework.exceptions import APIException


class BaseAPIException(APIException):
    status_code = status.HTTP_400_BAD_REQUEST
    code = "VALIDATION_ERROR"

    def __init__(self, detail=None, code=None):
        if detail is not None:
            self.detail = detail
        if code is not None:
            self.code = code

class ResourceNotFoundException(BaseAPIException):
    status_code = status.HTTP_404_NOT_FOUND
    code = "RESOURCE_NOT_FOUND"

class ForbiddenException(BaseAPIException):
    status_code = status.HTTP_403_FORBIDDEN
    code = "FORBIDDEN_ACCESS"

class GeminiProcessingException(BaseAPIException):
    status_code = status.HTTP_502_BAD_GATEWAY
    code = "GEMINI_ERROR"
