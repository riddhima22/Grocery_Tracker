from rest_framework import serializers

from .models import ScanCandidate, ScanImage, ScanSession


class ScanImageSerializer(serializers.ModelSerializer):
    class Meta:
        model = ScanImage
        fields = ('id', 'status', 'error_message', 'created_at')

class ScanCandidateSerializer(serializers.ModelSerializer):
    is_expiry_estimated = serializers.BooleanField(required=False, allow_null=True, default=False)

    class Meta:
        model = ScanCandidate
        fields = '__all__'
        read_only_fields = ('id', 'scan_session', 'source_image', 'created_at')

    def validate_is_expiry_estimated(self, value):
        if value is None:
            return None
        return bool(value)

    def validate(self, attrs):
        # Guarantee is_expiry_estimated is strictly boolean and never None
        is_est = attrs.get('is_expiry_estimated')
        if is_est is None:
            expiry = attrs.get('expiry_date', getattr(self.instance, 'expiry_date', None))
            estimated_dt = attrs.get('estimated_consumption_date', getattr(self.instance, 'estimated_consumption_date', None))
            date_type = attrs.get('date_type', getattr(self.instance, 'date_type', 'unknown'))
            date_source = attrs.get('date_source', getattr(self.instance, 'date_source', 'unknown'))

            if expiry is None and estimated_dt is None:
                attrs['is_expiry_estimated'] = False
            elif estimated_dt is not None or date_type == 'estimated' or date_source == 'calculated_shelf_life':
                attrs['is_expiry_estimated'] = True
            elif expiry is not None:
                attrs['is_expiry_estimated'] = False
            else:
                attrs['is_expiry_estimated'] = False
        else:
            attrs['is_expiry_estimated'] = bool(is_est)
        return attrs

class ScanSessionSerializer(serializers.ModelSerializer):
    images = ScanImageSerializer(many=True, read_only=True)

    class Meta:
        model = ScanSession
        fields = (
            'id', 'status', 'image_count', 'successful_image_count',
            'failed_image_count', 'candidate_count', 'idempotency_key',
            'completed_at', 'created_at', 'updated_at', 'images'
        )
        read_only_fields = ('id', 'status', 'image_count', 'successful_image_count', 'failed_image_count', 'candidate_count', 'completed_at', 'created_at', 'updated_at')
