from rest_framework.renderers import JSONRenderer


class WrappedJSONRenderer(JSONRenderer):
    def render(self, data, accepted_media_type=None, renderer_context=None):
        response = renderer_context.get('response') if renderer_context else None

        # Only wrap successful responses that aren't already formatted
        if response and response.status_code < 400:
            # If the response is 204 No Content, we don't wrap or change the data
            if response.status_code == 204:
                return super().render(data, accepted_media_type, renderer_context)

            if isinstance(data, dict) and ('success' in data or 'error' in data):
                # Already wrapped or error formatted by custom exception handler
                pass
            else:
                data = {
                    "success": True,
                    "data": data
                }

        return super().render(data, accepted_media_type, renderer_context)
