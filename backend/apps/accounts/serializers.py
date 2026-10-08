from rest_framework import serializers
from django.contrib.auth import get_user_model
from rest_framework.exceptions import ValidationError

User = get_user_model()

class UserRegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True)
    display_name = serializers.CharField(required=True, min_length=2, max_length=80)

    class Meta:
        model = User
        fields = ('email', 'password', 'display_name')

    def validate_email(self, value):
        norm_email = value.lower().strip()
        if User.objects.filter(email=norm_email).exists():
            raise ValidationError("An account with this email already exists.")
        return norm_email

    def validate_display_name(self, value):
        return value.strip()

    def create(self, validated_data):
        user = User.objects.create_user(
            email=validated_data['email'],
            password=validated_data['password'],
            display_name=validated_data['display_name']
        )
        return user

class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = (
            'id', 'email', 'display_name', 'avatar_url', 'email_verified',
            'diet_type', 'cuisine_pref', 'allergies', 'household_size',
            'notify_3_days', 'notify_1_day', 'notify_daily_recipe',
            'total_tracked', 'saved_from_waste', 'recipes_cooked'
        )
        read_only_fields = ('id', 'email', 'email_verified', 'total_tracked', 'saved_from_waste', 'recipes_cooked')

class PasswordResetSerializer(serializers.Serializer):
    email = serializers.EmailField()

    def validate_email(self, value):
        return value.lower().strip()


class PasswordResetConfirmSerializer(serializers.Serializer):
    token = serializers.CharField(required=True)
    password = serializers.CharField(required=False, min_length=8, write_only=True)
    new_password = serializers.CharField(required=False, min_length=8, write_only=True)

    def validate(self, attrs):
        pw = attrs.get('password') or attrs.get('new_password')
        if not pw:
            raise ValidationError("A new password with at least 8 characters is required.")
        attrs['password'] = pw
        return attrs


class VerifyEmailSerializer(serializers.Serializer):
    token = serializers.CharField(required=False, allow_blank=True)

