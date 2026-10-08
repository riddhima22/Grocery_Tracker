from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.db import models
import uuid

class UserManager(BaseUserManager):
    def create_user(self, email, password=None, **extra_fields):
        if not email:
            raise ValueError('The Email field must be set')
        email = self.normalize_email(email)
        user = self.model(email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        return self.create_user(email, password, **extra_fields)

class User(AbstractUser):
    objects = UserManager()
    
    # Overwrite username fields since email is the primary login
    username = None
    email = models.EmailField(unique=True)
    
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    display_name = models.CharField(max_length=80, blank=True)
    avatar_url = models.URLField(blank=True, null=True)
    email_verified = models.BooleanField(default=False)
    
    # Preferences
    diet_type = models.CharField(
        max_length=20, 
        choices=[('veg', 'Vegetarian'), ('non-veg', 'Non-Vegetarian'), ('any', 'Any')], 
        default='any'
    )
    cuisine_pref = models.CharField(max_length=100, blank=True)
    allergies = models.JSONField(default=list, blank=True)
    household_size = models.PositiveIntegerField(default=1)
    
    # Notifications Settings
    notify_3_days = models.BooleanField(default=True)
    notify_1_day = models.BooleanField(default=True)
    notify_daily_recipe = models.BooleanField(default=True)
    
    # Server-derived stats
    total_tracked = models.PositiveIntegerField(default=0)
    saved_from_waste = models.PositiveIntegerField(default=0)
    recipes_cooked = models.PositiveIntegerField(default=0)
    
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = []

    def __str__(self):
        return self.email


class EmailVerificationToken(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='verification_tokens')
    token = models.CharField(max_length=64, unique=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    is_used = models.BooleanField(default=False)

    @classmethod
    def create_for_user(cls, user, expires_hours=24):
        from django.utils import timezone
        import secrets
        from datetime import timedelta
        # Invalidate existing unused tokens for this user
        cls.objects.filter(user=user, is_used=False).update(is_used=True)
        token = secrets.token_urlsafe(32)
        expires_at = timezone.now() + timedelta(hours=expires_hours)
        return cls.objects.create(user=user, token=token, expires_at=expires_at)

    def is_valid(self):
        from django.utils import timezone
        return not self.is_used and timezone.now() < self.expires_at

    def __str__(self):
        return f"VerifyToken({self.user.email}, valid={self.is_valid()})"


class PasswordResetToken(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='password_reset_tokens')
    token = models.CharField(max_length=64, unique=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    is_used = models.BooleanField(default=False)

    @classmethod
    def create_for_user(cls, user, expires_hours=1):
        from django.utils import timezone
        import secrets
        from datetime import timedelta
        # Invalidate existing unused tokens for this user
        cls.objects.filter(user=user, is_used=False).update(is_used=True)
        token = secrets.token_urlsafe(32)
        expires_at = timezone.now() + timedelta(hours=expires_hours)
        return cls.objects.create(user=user, token=token, expires_at=expires_at)

    def is_valid(self):
        from django.utils import timezone
        return not self.is_used and timezone.now() < self.expires_at

    def __str__(self):
        return f"ResetToken({self.user.email}, valid={self.is_valid()})"

