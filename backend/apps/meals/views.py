import logging
from django.db import transaction
from django.utils import timezone
from rest_framework import viewsets, status, parsers
from rest_framework.decorators import action
from rest_framework.response import Response

from apps.groceries.models import GroceryItem
from apps.groceries.services import deduct_pantry_items_bulk
from integrations.ai.ai_service import AIService
from integrations.ai.gemini_client import AIContentBlockedError

from .models import MealLog, MealIngredientCandidate
from .serializers import MealLogSerializer

logger = logging.getLogger(__name__)

class MealLogViewSet(viewsets.ModelViewSet):
    serializer_class = MealLogSerializer
    parser_classes = [parsers.MultiPartParser, parsers.FormParser, parsers.JSONParser]

    def get_queryset(self):
        return MealLog.objects.filter(user=self.request.user).order_by('-created_at')

    def create(self, request, *args, **kwargs):
        user = request.user
        image_file = request.FILES.get('image')
        text_description = request.data.get('description', '')

        if not image_file and not text_description:
            return Response({'error': 'Please provide an image or a description of the meal.'}, status=status.HTTP_400_BAD_REQUEST)

        # Temp save image for AI inference (if we have an image)
        meal_log = MealLog(
            user=user,
            description=text_description,
            status=MealLog.StatusChoices.PENDING_CONFIRMATION
        )
        if image_file:
            meal_log.image = image_file
        
        # Save so image is on disk and we have an ID
        meal_log.save()
        
        # Gather pantry items
        groceries = GroceryItem.objects.filter(user=user, quantity__gt=0).exclude(status='expired')
        grocery_data = []
        for g in groceries:
            grocery_data.append({
                "pantry_item_id": str(g.id),
                "name": g.name,
                "quantity": float(g.quantity),
                "unit": g.unit,
                "status": g.status
            })

        ai_service = AIService()
        image_path = meal_log.image.path if meal_log.image else None
        
        try:
            ai_output = ai_service.infer_meal_ingredients(image_path, text_description, grocery_data)
        except AIContentBlockedError as e:
            logger.warning(f"Meal inference content blocked: {e}")
            meal_log.delete()
            return Response({
                'success': False,
                'error': "The image couldn't be analyzed — try a clearer photo or a different angle."
            }, status=status.HTTP_400_BAD_REQUEST)
        except Exception as e:
            logger.error(f"Meal inference failed: {e}", exc_info=True)
            meal_log.delete()
            return Response({
                'success': False,
                'message': 'Meal inference failed. Please try again later.',
                'error': {
                    'code': 'MEAL_INFERENCE_FAILED',
                    'message': 'Meal inference failed.',
                    'details': str(e),
                }
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

        meal_log.name = ai_output.get('meal_name', 'Unknown Meal')
        if ai_output.get('description') and not text_description:
            meal_log.description = ai_output.get('description')
        meal_log.save()

        with transaction.atomic():
            candidates = []
            for item in ai_output.get('ingredients', []):
                p_item_id = item.get('pantry_item_id')
                pantry_item_ref = None
                if p_item_id:
                    try:
                        pantry_item_ref = GroceryItem.objects.get(id=p_item_id, user=user)
                    except (GroceryItem.DoesNotExist, Exception):
                        pass
                
                candidates.append(MealIngredientCandidate(
                    meal_log=meal_log,
                    pantry_item=pantry_item_ref,
                    name=item.get('name', 'Unknown'),
                    estimated_quantity=item.get('estimated_quantity', 0),
                    deduct_quantity=item.get('estimated_quantity', 0),
                    unit=item.get('unit', 'pcs'),
                    confidence=item.get('confidence', 'Low'),
                    confirmed=True if pantry_item_ref else False
                ))
            
            MealIngredientCandidate.objects.bulk_create(candidates)

        serializer = self.get_serializer(meal_log)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'], url_path='confirm-deduction')
    def confirm_deduction(self, request, pk=None):
        meal_log_obj = self.get_object()
        user = request.user

        with transaction.atomic():
            # Row-level lock on MealLog to prevent concurrent double confirmation
            meal_log = MealLog.objects.select_for_update().get(pk=meal_log_obj.pk)

            # Idempotent replay if already confirmed
            if meal_log.status == MealLog.StatusChoices.CONFIRMED:
                serializer = self.get_serializer(meal_log)
                cached = meal_log.deduction_result or {}
                return Response({
                    "success": True,
                    "data": serializer.data,
                    "deduction_summary": cached.get('summary', []),
                    "deduction_errors": cached.get('errors', []),
                    "already_confirmed": True,
                    "message": "Meal was already confirmed (idempotent replay)."
                })

            if meal_log.status != MealLog.StatusChoices.PENDING_CONFIRMATION:
                return Response({'error': f'Meal cannot be confirmed because status is {meal_log.status}.'}, status=status.HTTP_400_BAD_REQUEST)

            candidate_deductions = request.data.get('candidate_deductions', [])
            items_to_deduct = []

            for c_data in candidate_deductions:
                c_id = c_data.get('candidate_id')
                confirmed = c_data.get('confirmed', False)
                quantity = c_data.get('quantity', 0)
                
                try:
                    candidate = MealIngredientCandidate.objects.select_for_update().get(id=c_id, meal_log=meal_log)
                except MealIngredientCandidate.DoesNotExist:
                    continue
                
                candidate.confirmed = confirmed
                candidate.deduct_quantity = quantity
                candidate.save(update_fields=['confirmed', 'deduct_quantity'])
                
                if confirmed and quantity > 0:
                    items_to_deduct.append({
                        'pantry_item_id': str(candidate.pantry_item.id) if candidate.pantry_item else None,
                        'name': candidate.name,
                        'quantity': quantity,
                        'unit': candidate.unit
                    })
            
            summary, errors = deduct_pantry_items_bulk(user, items_to_deduct, activity_source='meal_log')
            
            meal_log.status = MealLog.StatusChoices.CONFIRMED
            meal_log.confirmed_at = timezone.now()
            meal_log.deduction_result = {
                'summary': summary,
                'errors': errors
            }
            meal_log.save(update_fields=['status', 'confirmed_at', 'deduction_result', 'updated_at'])
            
            serializer = self.get_serializer(meal_log)
            
            return Response({
                "success": True,
                "data": serializer.data,
                "deduction_summary": summary,
                "deduction_errors": errors,
                "message": "Meal logged and pantry items deducted."
            })
