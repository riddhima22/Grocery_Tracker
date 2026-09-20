import logging
from decimal import Decimal
from django.db import transaction
from django.utils import timezone
from .models import GroceryItem, GroceryActivity

logger = logging.getLogger(__name__)

def deduct_pantry_items_bulk(user, items_to_deduct, activity_source='meal_log'):
    """
    Deducts items from a user's pantry cleanly in a transaction.
    `items_to_deduct`: List of dicts, e.g. [{'pantry_item_id': UUID/str, 'name': str, 'quantity': float, 'unit': str}]
    Returns (deducted_items_summary_list, errors_list)
    """
    summary = []
    errors = []

    with transaction.atomic():
        for item_data in items_to_deduct:
            pantry_item_id = item_data.get('pantry_item_id')
            item_name = item_data.get('name', 'Unknown Item')
            quantity_to_deduct = Decimal(str(item_data.get('quantity', 0)))
            
            if quantity_to_deduct <= 0:
                continue
                
            grocery_item = None
            
            if pantry_item_id:
                try:
                    grocery_item = GroceryItem.objects.select_for_update().get(id=pantry_item_id, user=user)
                except GroceryItem.DoesNotExist:
                    pass
            
            if not grocery_item:
                grocery_item = GroceryItem.objects.select_for_update().filter(
                    user=user, 
                    name__iexact=item_name, 
                    quantity__gt=0
                ).order_by('expiry_date').first()

            if not grocery_item:
                errors.append(f"Item '{item_name}' not found or out of stock in pantry.")
                continue
            
            prev_quantity = grocery_item.quantity
            new_quantity = prev_quantity - quantity_to_deduct
            
            if new_quantity <= 0:
                grocery_item.quantity = Decimal('0')
                grocery_item.status = 'expired'
                try:
                    from apps.grocery_lists.services import add_to_active_grocery_list
                    add_to_active_grocery_list(
                        user=user,
                        name=grocery_item.name,
                        unit=grocery_item.unit,
                        quantity=1.0,
                        reason=f"Finished during cooking ({grocery_item.name}).",
                        source_signal='recipe_cooked_finish'
                    )
                except Exception as e:
                    logger.warning(f"Could not auto-add finished item to grocery list: {e}")
            else:
                grocery_item.quantity = new_quantity
            
            grocery_item.save()

            # Record Activity
            GroceryActivity.objects.create(
                user=user,
                grocery_item=grocery_item,
                activity_type=GroceryActivity.ActivityTypes.CONSUMED,
                previous_quantity=prev_quantity,
                new_quantity=grocery_item.quantity,
                unit=grocery_item.unit,
                metadata={'source': activity_source, 'deducted_amount': float(quantity_to_deduct)}
            )
            
            # Update user stats
            if grocery_item.expiry_date and grocery_item.expiry_date >= timezone.now().date():
                user.saved_from_waste += 1
                user.save(update_fields=['saved_from_waste'])
                
            summary.append({
                'pantry_item_id': str(grocery_item.id),
                'name': grocery_item.name,
                'deducted_quantity': float(prev_quantity - grocery_item.quantity),
                'remaining_quantity': float(grocery_item.quantity),
                'unit': grocery_item.unit
            })
            
    return summary, errors
