from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('notifications', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='devicetoken',
            name='platform',
            field=models.CharField(blank=True, default='android', max_length=20),
        ),
        migrations.AddField(
            model_name='devicetoken',
            name='device_id',
            field=models.CharField(blank=True, max_length=255, null=True),
        ),
        migrations.AddField(
            model_name='devicetoken',
            name='is_active',
            field=models.BooleanField(default=True),
        ),
        migrations.AddIndex(
            model_name='devicetoken',
            index=models.Index(fields=['user', 'is_active'], name='notif_user_active_idx'),
        ),
        migrations.AddIndex(
            model_name='devicetoken',
            index=models.Index(fields=['token'], name='notif_token_idx'),
        ),
    ]
