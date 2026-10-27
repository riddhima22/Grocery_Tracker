from datetime import timedelta
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import EmailVerificationToken, PasswordResetToken

User = get_user_model()


class AuthTests(APITestCase):
    def setUp(self):
        self.register_url = reverse('register')
        self.login_url = reverse('token_obtain_pair')
        self.me_url = reverse('user_profile')
        self.google_url = reverse('google_login')
        self.apple_url = reverse('apple_login')
        self.verify_email_url = reverse('verify_email')
        self.resend_verify_url = reverse('resend_verification')
        self.forgot_pw_url = reverse('forgot_password')
        self.reset_pw_url = reverse('reset_password')
        self.profile_account_url = reverse('profile_account_delete')

        self.user_data = {
            'email': 'test@example.com',
            'password': 'testPassword123!',
            'display_name': 'Test User'
        }

    def test_user_registration(self):
        """Ensure we can register a new user, get tokens, and create verification token."""
        response = self.client.post(self.register_url, self.user_data, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(response.data['success'])
        self.assertIn('tokens', response.data['data'])
        self.assertIn('access', response.data['data']['tokens'])

        user = User.objects.get(email='test@example.com')
        self.assertFalse(user.email_verified)
        token_obj = EmailVerificationToken.objects.filter(user=user, is_used=False).first()
        self.assertIsNotNone(token_obj)

    def test_user_login(self):
        """Ensure we can login with registered credentials."""
        User.objects.create_user(
            email='login@example.com',
            password='loginPassword123!',
            display_name='Login User'
        )
        data = {
            'email': 'login@example.com',
            'password': 'loginPassword123!'
        }
        response = self.client.post(self.login_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)
        self.assertIn('refresh', response.data)

    def test_get_profile_requires_auth(self):
        """Ensure unauthenticated users cannot access profile data."""
        response = self.client.get(self.me_url)
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_avatar_upload_validation(self):
        """Ensure fake images or mismatched image extensions are rejected with 400."""
        user = User.objects.create_user(
            email='avatar_test@example.com',
            password='Password123!',
            display_name='Avatar Tester'
        )
        self.client.force_authenticate(user=user)
        import io

        from django.core.files.uploadedfile import SimpleUploadedFile
        from PIL import Image

        fake_file = SimpleUploadedFile("avatar.png", b"not-a-valid-png-stream", content_type="image/png")
        res = self.client.patch(self.me_url, {'avatar': fake_file}, format='multipart')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(res.data['success'])

        buf = io.BytesIO()
        Image.new('RGB', (10, 10), color='green').save(buf, format='PNG')
        buf.seek(0)
        mismatch_file = SimpleUploadedFile("avatar.jpg", buf.read(), content_type="image/jpeg")
        res = self.client.patch(self.me_url, {'avatar': mismatch_file}, format='multipart')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(res.data['success'])

        buf2 = io.BytesIO()
        Image.new('RGB', (10, 10), color='green').save(buf2, format='JPEG')
        buf2.seek(0)
        valid_file = SimpleUploadedFile("avatar.jpg", buf2.read(), content_type="image/jpeg")
        res = self.client.patch(self.me_url, {'avatar': valid_file}, format='multipart')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertTrue(res.data['success'])


class SecurityAuthTests(APITestCase):
    def setUp(self):
        self.google_url = reverse('google_login')
        self.apple_url = reverse('apple_login')
        self.verify_email_url = reverse('verify_email')
        self.resend_verify_url = reverse('resend_verification')
        self.forgot_pw_url = reverse('forgot_password')
        self.reset_pw_url = reverse('reset_password')
        self.me_url = reverse('user_profile')
        self.profile_account_url = reverse('profile_account_delete')

    # --- GOOGLE AUTH TESTS ---
    def test_google_login_rejects_email_only(self):
        """Email-only login without verified ID token must be rejected."""
        res = self.client.post(self.google_url, {'email': 'victim@example.com'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(res.data['success'])

    def test_google_login_rejects_fake_token(self):
        """Unverified/fake Google token must be rejected with 401."""
        res = self.client.post(self.google_url, {'token': 'fake.unverified.token'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertFalse(res.data['success'])

    @patch('apps.accounts.views._verify_google_id_token')
    def test_google_login_succeeds_with_verified_token(self, mock_verify):
        """Cryptographically verified Google token creates/authenticates user."""
        mock_verify.return_value = {
            'email': 'google_verified@example.com',
            'name': 'Google Verified User',
            'sub': '1234567890',
            'email_verified': True,
        }
        res = self.client.post(self.google_url, {'token': 'valid.google.jwt'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertTrue(res.data['success'])
        self.assertIn('tokens', res.data['data'])
        self.assertTrue(User.objects.filter(email='google_verified@example.com').exists())

    # --- APPLE AUTH TESTS ---
    def test_apple_login_rejects_email_only(self):
        """Email-only login without verified ID token must be rejected."""
        res = self.client.post(self.apple_url, {'email': 'victim@example.com'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(res.data['success'])

    def test_apple_login_rejects_fake_token(self):
        """Unverified/fake Apple token must be rejected with 401."""
        res = self.client.post(self.apple_url, {'token': 'fake.apple.token'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertFalse(res.data['success'])

    @patch('apps.accounts.views._verify_apple_identity_token')
    def test_apple_login_succeeds_with_verified_token(self, mock_verify):
        """Cryptographically verified Apple token creates/authenticates user."""
        mock_verify.return_value = {
            'email': 'apple_verified@example.com',
            'sub': 'apple.sub.123',
            'email_verified': True,
        }
        res = self.client.post(self.apple_url, {'token': 'valid.apple.jwt'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertTrue(res.data['success'])
        self.assertIn('tokens', res.data['data'])
        self.assertTrue(User.objects.filter(email='apple_verified@example.com').exists())

    # --- EMAIL VERIFICATION TESTS ---
    def test_verify_email_without_token_rejects_unverified_user(self):
        """Calling /verify-email/ without token must NOT verify an unverified user."""
        user = User.objects.create_user(
            email='unverified@example.com',
            password='Password123!',
            email_verified=False
        )
        self.client.force_authenticate(user=user)
        res = self.client.post(self.verify_email_url, {}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        user.refresh_from_db()
        self.assertFalse(user.email_verified)

    def test_verify_email_with_valid_token_succeeds(self):
        """Valid token marks email_verified=True and invalidates token."""
        user = User.objects.create_user(
            email='verify_me@example.com',
            password='Password123!',
            email_verified=False
        )
        token_obj = EmailVerificationToken.create_for_user(user)
        res = self.client.post(self.verify_email_url, {'token': token_obj.token}, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        user.refresh_from_db()
        self.assertTrue(user.email_verified)
        token_obj.refresh_from_db()
        self.assertTrue(token_obj.is_used)

        # Re-using the same token must fail
        res2 = self.client.post(self.verify_email_url, {'token': token_obj.token}, format='json')
        self.assertEqual(res2.status_code, status.HTTP_400_BAD_REQUEST)

    def test_verify_email_with_expired_token_fails(self):
        """Expired verification token must be rejected."""
        user = User.objects.create_user(
            email='expired@example.com',
            password='Password123!',
            email_verified=False
        )
        token_obj = EmailVerificationToken.objects.create(
            user=user,
            token='expired_token_123',
            expires_at=timezone.now() - timedelta(minutes=10)
        )
        res = self.client.post(self.verify_email_url, {'token': token_obj.token}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        user.refresh_from_db()
        self.assertFalse(user.email_verified)

    def test_resend_verification_generates_new_token(self):
        """Resend generates a new token and invalidates old one."""
        user = User.objects.create_user(
            email='resend@example.com',
            password='Password123!',
            email_verified=False
        )
        old_token = EmailVerificationToken.create_for_user(user)
        self.client.force_authenticate(user=user)
        res = self.client.post(self.resend_verify_url, {}, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)

        old_token.refresh_from_db()
        self.assertTrue(old_token.is_used)
        new_token = EmailVerificationToken.objects.filter(user=user, is_used=False).first()
        self.assertIsNotNone(new_token)
        self.assertNotEqual(old_token.token, new_token.token)

    # --- PASSWORD RESET TESTS ---
    def test_forgot_password_generic_safe_response(self):
        """Forgot password always returns generic response for registered and unregistered emails."""
        res_nonexistent = self.client.post(self.forgot_pw_url, {'email': 'nobody@example.com'}, format='json')
        self.assertEqual(res_nonexistent.status_code, status.HTTP_200_OK)
        self.assertTrue(res_nonexistent.data['success'])

        user = User.objects.create_user(email='existing@example.com', password='OldPassword123!')
        res_existing = self.client.post(self.forgot_pw_url, {'email': 'existing@example.com'}, format='json')
        self.assertEqual(res_existing.status_code, status.HTTP_200_OK)
        self.assertTrue(res_existing.data['success'])
        self.assertTrue(PasswordResetToken.objects.filter(user=user, is_used=False).exists())

    def test_reset_password_with_valid_token_updates_password(self):
        """Reset password updates user password and marks token used."""
        user = User.objects.create_user(email='reset_target@example.com', password='OldPassword123!')
        token_obj = PasswordResetToken.create_for_user(user)

        res = self.client.post(self.reset_pw_url, {
            'token': token_obj.token,
            'password': 'NewSecurePassword456!'
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)

        user.refresh_from_db()
        self.assertTrue(user.check_password('NewSecurePassword456!'))
        token_obj.refresh_from_db()
        self.assertTrue(token_obj.is_used)

        # Repeated use of token must be rejected
        res2 = self.client.post(self.reset_pw_url, {
            'token': token_obj.token,
            'password': 'AnotherPassword789!'
        }, format='json')
        self.assertEqual(res2.status_code, status.HTTP_400_BAD_REQUEST)

    # --- ACCOUNT DELETION TESTS ---
    def test_delete_account_via_me_endpoint(self):
        """User can delete their account via DELETE /auth/me/."""
        user = User.objects.create_user(email='delete_me@example.com', password='Password123!')
        self.client.force_authenticate(user=user)
        res = self.client.delete(self.me_url)
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertFalse(User.objects.filter(email='delete_me@example.com').exists())

    def test_delete_account_via_profile_account_endpoint(self):
        """User can delete their account via DELETE /profile/account/ (Flutter contract)."""
        user = User.objects.create_user(email='delete_profile@example.com', password='Password123!')
        self.client.force_authenticate(user=user)
        res = self.client.delete(self.profile_account_url)
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertFalse(User.objects.filter(email='delete_profile@example.com').exists())
