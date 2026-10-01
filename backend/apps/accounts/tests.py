from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase
from django.contrib.auth import get_user_model

User = get_user_model()

class AuthTests(APITestCase):
    def setUp(self):
        self.register_url = reverse('register')
        self.login_url = reverse('token_obtain_pair')
        self.me_url = reverse('user_profile')
        self.user_data = {
            'email': 'test@example.com',
            'password': 'testPassword123!',
            'display_name': 'Test User'
        }

    def test_user_registration(self):
        """Ensure we can register a new user and get back JWT tokens."""
        response = self.client.post(self.register_url, self.user_data, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(response.data['success'])
        self.assertIn('tokens', response.data['data'])
        self.assertIn('access', response.data['data']['tokens'])

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
        from django.core.files.uploadedfile import SimpleUploadedFile
        import io
        from PIL import Image

        # 1. Non-image content with valid extension
        fake_file = SimpleUploadedFile("avatar.png", b"not-a-valid-png-stream", content_type="image/png")
        res = self.client.patch(self.me_url, {'avatar': fake_file}, format='multipart')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(res.data['success'])

        # 2. Format mismatch (PNG content claiming to be .jpg)
        buf = io.BytesIO()
        Image.new('RGB', (10, 10), color='green').save(buf, format='PNG')
        buf.seek(0)
        mismatch_file = SimpleUploadedFile("avatar.jpg", buf.read(), content_type="image/jpeg")
        res = self.client.patch(self.me_url, {'avatar': mismatch_file}, format='multipart')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(res.data['success'])

        # 3. Valid image content and extension succeeds
        buf2 = io.BytesIO()
        Image.new('RGB', (10, 10), color='green').save(buf2, format='JPEG')
        buf2.seek(0)
        valid_file = SimpleUploadedFile("avatar.jpg", buf2.read(), content_type="image/jpeg")
        res = self.client.patch(self.me_url, {'avatar': valid_file}, format='multipart')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertTrue(res.data['success'])
