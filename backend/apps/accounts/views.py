from rest_framework import status, generics
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework_simplejwt.tokens import RefreshToken
from django.contrib.auth import get_user_model
from rest_framework.throttling import UserRateThrottle
from django.core.mail import send_mail
from django.conf import settings
from .serializers import (
    UserRegisterSerializer,
    UserSerializer,
    PasswordResetSerializer,
    PasswordResetConfirmSerializer,
    VerifyEmailSerializer,
)
from .models import EmailVerificationToken, PasswordResetToken
import os
import logging
import requests
import json
import jwt
from jwt.algorithms import RSAAlgorithm
from google.oauth2 import id_token as google_id_token
from google.auth.transport import requests as google_requests

User = get_user_model()
logger = logging.getLogger('freshtrack.accounts')

APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys"
_apple_keys_cache = None


class RegisterThrottle(UserRateThrottle):
    rate = '5/minute'


class RegisterView(generics.CreateAPIView):
    authentication_classes = ()
    permission_classes = (AllowAny,)
    serializer_class = UserRegisterSerializer
    throttle_classes = [RegisterThrottle]

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()

        # Generate single-use verification token
        verification_token = EmailVerificationToken.create_for_user(user)

        # Dispatch verification email
        try:
            subject = "Verify your FreshTrack account"
            message = (
                f"Hi {user.display_name},\n\n"
                f"Welcome to FreshTrack! Please verify your email using the verification code below:\n\n"
                f"{verification_token.token}\n\n"
                f"This code will expire in 24 hours.\n\n"
                f"Best,\nThe FreshTrack Team"
            )
            from_email = getattr(settings, 'DEFAULT_FROM_EMAIL', 'noreply@freshtrack.app')
            send_mail(subject, message, from_email, [user.email], fail_silently=True)
        except Exception as e:
            logger.warning(f"Failed to send verification email to {user.email}: {e}")

        refresh = RefreshToken.for_user(user)

        return Response({
            "success": True,
            "data": {
                "user": UserSerializer(user).data,
                "tokens": {
                    "refresh": str(refresh),
                    "access": str(refresh.access_token),
                }
            },
            "message": "User registered successfully. Verification email sent."
        }, status=status.HTTP_201_CREATED)


class MeView(APIView):
    permission_classes = (IsAuthenticated,)

    def get(self, request):
        serializer = UserSerializer(request.user)
        return Response({
            "success": True,
            "data": serializer.data
        })

    def patch(self, request):
        user = request.user
        avatar_file = request.FILES.get('avatar')
        if avatar_file:
            ext = os.path.splitext(avatar_file.name)[1].lower()
            allowed_formats = {
                '.jpg': 'JPEG',
                '.jpeg': 'JPEG',
                '.png': 'PNG',
                '.webp': 'WEBP',
            }
            if ext not in allowed_formats:
                return Response({"success": False, "error": "Unsupported image format. Allowed: JPG, JPEG, PNG, WEBP"}, status=400)
            if avatar_file.size > 2 * 1024 * 1024:
                return Response({"success": False, "error": "Image size exceeds 2MB limit."}, status=400)

            try:
                avatar_file.seek(0)
                from PIL import Image
                with Image.open(avatar_file) as pil_img:
                    pil_img.verify()
                    actual_format = pil_img.format
                if actual_format != allowed_formats[ext]:
                    return Response({
                        "success": False,
                        "error": f"Image format mismatch: file content is {actual_format}, but extension is {ext}."
                    }, status=400)
            except Exception:
                return Response({"success": False, "error": "Uploaded file is not a valid image."}, status=400)
            finally:
                avatar_file.seek(0)

            from django.core.files.storage import default_storage
            filename = f"avatars/{user.id}{ext}"

            if default_storage.exists(filename):
                default_storage.delete(filename)

            path = default_storage.save(filename, avatar_file)
            media_path = settings.MEDIA_URL + path
            if not media_path.startswith('/'):
                media_path = '/' + media_path
            user.avatar_url = request.build_absolute_uri(media_path)
            user.save(update_fields=['avatar_url'])

        serializer = UserSerializer(user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response({
            "success": True,
            "data": serializer.data,
            "message": "Preferences updated successfully."
        })

    def delete(self, request):
        """Secure account deletion endpoint."""
        user = request.user
        logger.info(f"Account deletion initiated for user: {user.email} (id: {user.id})")
        user.delete()
        return Response({
            "success": True,
            "message": "Account has been permanently deleted."
        }, status=status.HTTP_200_OK)


class DeleteAccountView(APIView):
    """Dedicated alias endpoint for Flutter's /profile/account/ route."""
    permission_classes = (IsAuthenticated,)

    def delete(self, request):
        user = request.user
        logger.info(f"Account deletion via /profile/account/ for user: {user.email}")
        user.delete()
        return Response({
            "success": True,
            "message": "Account has been permanently deleted."
        }, status=status.HTTP_200_OK)


class ForgotPasswordView(APIView):
    authentication_classes = ()
    permission_classes = (AllowAny,)

    def post(self, request):
        serializer = PasswordResetSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = serializer.validated_data['email']

        user = User.objects.filter(email=email).first()
        if user:
            reset_token = PasswordResetToken.create_for_user(user)
            try:
                subject = "Reset your FreshTrack password"
                message = (
                    f"Hi {user.display_name},\n\n"
                    f"You requested a password reset for your FreshTrack account.\n"
                    f"Use the reset token below to reset your password:\n\n"
                    f"{reset_token.token}\n\n"
                    f"This token will expire in 1 hour. If you did not request this, please ignore this email.\n\n"
                    f"Best,\nThe FreshTrack Team"
                )
                from_email = getattr(settings, 'DEFAULT_FROM_EMAIL', 'noreply@freshtrack.app')
                send_mail(subject, message, from_email, [user.email], fail_silently=True)
                logger.info(f"Password reset token generated and email dispatched for: {email}")
            except Exception as e:
                logger.warning(f"Failed to send password reset email to {email}: {e}")

        # Always return safe generic response to prevent user enumeration
        return Response({
            "success": True,
            "data": {},
            "message": "If this email is registered, we have sent a reset password link."
        })


class ResetPasswordView(APIView):
    authentication_classes = ()
    permission_classes = (AllowAny,)

    def post(self, request):
        serializer = PasswordResetConfirmSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        token_str = serializer.validated_data['token']
        new_password = serializer.validated_data['password']

        reset_token = PasswordResetToken.objects.filter(token=token_str).first()
        if not reset_token or not reset_token.is_valid():
            return Response({
                "success": False,
                "error": "Invalid, expired, or already used password reset token."
            }, status=status.HTTP_400_BAD_REQUEST)

        user = reset_token.user
        user.set_password(new_password)
        user.save(update_fields=['password'])

        # Mark token as used
        reset_token.is_used = True
        reset_token.save(update_fields=['is_used'])

        logger.info(f"Password reset successful for user: {user.email}")
        return Response({
            "success": True,
            "data": {},
            "message": "Password has been reset successfully. You can now log in with your new password."
        }, status=status.HTTP_200_OK)


class VerifyEmailView(APIView):
    authentication_classes = ()
    permission_classes = (AllowAny,)

    def post(self, request):
        token_str = request.data.get('token') or request.query_params.get('token')

        # Case 1: Token provided (via link click or manual code entry)
        if token_str:
            token_obj = EmailVerificationToken.objects.filter(token=token_str).first()
            if not token_obj or not token_obj.is_valid():
                return Response({
                    "success": False,
                    "error": "Invalid, expired, or already used verification token."
                }, status=status.HTTP_400_BAD_REQUEST)

            token_obj.is_used = True
            token_obj.save(update_fields=['is_used'])

            user = token_obj.user
            user.email_verified = True
            user.save(update_fields=['email_verified'])

            return Response({
                "success": True,
                "data": {"email_verified": True},
                "message": "Email verified successfully."
            }, status=status.HTTP_200_OK)

        # Case 2: No token provided - require authenticated session to inspect verified state
        # (Flutter's "I have verified my email" check button)
        user = request.user
        if not user or not user.is_authenticated:
            # Try parsing authorization header manually if provided
            auth_header = request.headers.get('Authorization', '')
            if auth_header.startswith('Bearer '):
                from rest_framework_simplejwt.authentication import JWTAuthentication
                try:
                    validated_token = JWTAuthentication().get_validated_token(auth_header.split(' ')[1])
                    user = JWTAuthentication().get_user(validated_token)
                except Exception:
                    pass

        if user and user.is_authenticated:
            if user.email_verified:
                return Response({
                    "success": True,
                    "data": {"email_verified": True},
                    "message": "Email is already verified."
                }, status=status.HTTP_200_OK)
            else:
                return Response({
                    "success": False,
                    "error": "Email is not verified. Please check your verification email link.",
                    "data": {"email_verified": False}
                }, status=status.HTTP_400_BAD_REQUEST)

        return Response({
            "success": False,
            "error": "Verification token is required."
        }, status=status.HTTP_400_BAD_REQUEST)


class ResendVerificationView(APIView):
    permission_classes = (IsAuthenticated,)

    def post(self, request):
        user = request.user
        if user.email_verified:
            return Response({
                "success": True,
                "data": {"email_verified": True},
                "message": "Email is already verified."
            })

        # Generate a fresh verification token
        token_obj = EmailVerificationToken.create_for_user(user)

        try:
            subject = "Verify your FreshTrack account"
            message = (
                f"Hi {user.display_name},\n\n"
                f"Here is your new FreshTrack verification code:\n\n"
                f"{token_obj.token}\n\n"
                f"This code will expire in 24 hours.\n\n"
                f"Best,\nThe FreshTrack Team"
            )
            from_email = getattr(settings, 'DEFAULT_FROM_EMAIL', 'noreply@freshtrack.app')
            send_mail(subject, message, from_email, [user.email], fail_silently=True)
            logger.info(f"Resent verification email to: {user.email}")
        except Exception as e:
            logger.warning(f"Failed to resend verification email to {user.email}: {e}")

        return Response({
            "success": True,
            "data": {},
            "message": "Verification code has been resent to your email."
        })


def _verify_google_id_token(token_str):
    """
    Cryptographically verify a Google ID token or Firebase ID token.
    Validates:
    - Signature
    - Issuer (accounts.google.com or https://accounts.google.com)
    - Expiration
    - Audience (if GOOGLE_CLIENT_ID configured in settings)
    """
    # 1. Try google.oauth2.id_token verification
    req = google_requests.Request()
    google_client_id = getattr(settings, 'GOOGLE_CLIENT_ID', None) or None

    try:
        id_info = google_id_token.verify_oauth2_token(
            token_str,
            req,
            audience=google_client_id,
            clock_skew_in_seconds=10
        )
        issuer = id_info.get('iss')
        if issuer not in ['accounts.google.com', 'https://accounts.google.com']:
            raise ValueError(f"Invalid Google token issuer: {issuer}")
        return id_info
    except Exception as e:
        logger.debug(f"google.oauth2 verification failed: {e}")

    # 2. Try Firebase Admin verification if configured
    try:
        import firebase_admin
        from firebase_admin import auth as firebase_auth
        if getattr(firebase_admin, '_apps', None):
            decoded = firebase_auth.verify_id_token(token_str)
            return decoded
    except Exception as e:
        logger.debug(f"Firebase token verification failed: {e}")

    return None


def _verify_apple_identity_token(token_str):
    """
    Cryptographically verify an Apple identity token against Apple's JWKS.
    Validates:
    - Signature using Apple's published RS256 public keys
    - Issuer: https://appleid.apple.com
    - Expiration
    - Audience (if APPLE_CLIENT_ID configured in settings)
    """
    global _apple_keys_cache
    try:
        header = jwt.get_unverified_header(token_str)
        kid = header.get('kid')
        if not kid:
            return None

        # Fetch Apple JWKS
        if not _apple_keys_cache:
            resp = requests.get(APPLE_KEYS_URL, timeout=5)
            if resp.status_code == 200:
                _apple_keys_cache = resp.json().get('keys', [])

        matching_key = None
        for k in (_apple_keys_cache or []):
            if k.get('kid') == kid:
                matching_key = k
                break

        # If key not found in cache, re-fetch once
        if not matching_key:
            resp = requests.get(APPLE_KEYS_URL, timeout=5)
            if resp.status_code == 200:
                _apple_keys_cache = resp.json().get('keys', [])
                for k in _apple_keys_cache:
                    if k.get('kid') == kid:
                        matching_key = k
                        break

        if not matching_key:
            logger.warning(f"No matching Apple public key for kid: {kid}")
            return None

        public_key = RSAAlgorithm.from_jwk(json.dumps(matching_key))
        apple_client_id = getattr(settings, 'APPLE_CLIENT_ID', None) or None

        payload = jwt.decode(
            token_str,
            public_key,
            algorithms=['RS256'],
            audience=apple_client_id,
            issuer='https://appleid.apple.com',
            options={
                'verify_exp': True,
                'verify_aud': bool(apple_client_id),
                'verify_iss': True,
            }
        )
        return payload
    except Exception as e:
        logger.warning(f"Apple identity token verification failed: {e}")
        return None


class GoogleLoginView(APIView):
    authentication_classes = ()
    permission_classes = (AllowAny,)
    throttle_classes = ()

    def post(self, request):
        token = request.data.get('token')
        if not token:
            return Response({
                "success": False,
                "error": "Google identity token is required."
            }, status=status.HTTP_400_BAD_REQUEST)

        # Cryptographically verify the token — NEVER trust client-provided email
        id_info = _verify_google_id_token(token)
        if not id_info:
            return Response({
                "success": False,
                "error": "Invalid, expired, or unverified Google identity token."
            }, status=status.HTTP_401_UNAUTHORIZED)

        email = id_info.get('email')
        if not email:
            return Response({
                "success": False,
                "error": "Google token does not contain an email address."
            }, status=status.HTTP_401_UNAUTHORIZED)

        # Ensure email is verified by Google
        if not id_info.get('email_verified', True):
            return Response({
                "success": False,
                "error": "Google account email is not verified."
            }, status=status.HTTP_401_UNAUTHORIZED)

        name = id_info.get('name') or request.data.get('name') or 'Google User'

        user, created = User.objects.get_or_create(
            email=email.lower().strip(),
            defaults={
                'display_name': name,
                'email_verified': True,
            }
        )
        if created:
            user.email_verified = True
            user.save(update_fields=['email_verified'])

        refresh = RefreshToken.for_user(user)
        return Response({
            "success": True,
            "data": {
                "user": UserSerializer(user).data,
                "tokens": {
                    "refresh": str(refresh),
                    "access": str(refresh.access_token),
                }
            },
            "message": "Logged in with Google successfully."
        }, status=status.HTTP_200_OK)


class AppleLoginView(APIView):
    authentication_classes = ()
    permission_classes = (AllowAny,)
    throttle_classes = ()

    def post(self, request):
        token = request.data.get('token')
        if not token:
            return Response({
                "success": False,
                "error": "Apple identity token is required."
            }, status=status.HTTP_400_BAD_REQUEST)

        # Cryptographically verify the Apple identity token
        payload = _verify_apple_identity_token(token)
        if not payload:
            return Response({
                "success": False,
                "error": "Invalid, expired, or unverified Apple identity token."
            }, status=status.HTTP_401_UNAUTHORIZED)

        sub = payload.get('sub')
        if not sub:
            return Response({
                "success": False,
                "error": "Apple token missing subject identifier."
            }, status=status.HTTP_401_UNAUTHORIZED)

        # Use token's verified email if present; fallback to stable private relay sub email
        email = payload.get('email')
        if not email:
            email = f"apple_{sub[:12]}@privaterelay.appleid.com"

        name = request.data.get('name') or 'Apple User'

        user, created = User.objects.get_or_create(
            email=email.lower().strip(),
            defaults={
                'display_name': name,
                'email_verified': True,
            }
        )
        if created:
            user.email_verified = True
            user.save(update_fields=['email_verified'])

        refresh = RefreshToken.for_user(user)
        return Response({
            "success": True,
            "data": {
                "user": UserSerializer(user).data,
                "tokens": {
                    "refresh": str(refresh),
                    "access": str(refresh.access_token),
                }
            },
            "message": "Logged in with Apple successfully."
        }, status=status.HTTP_200_OK)
