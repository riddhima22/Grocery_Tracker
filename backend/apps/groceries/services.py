import logging
from decimal import Decimal
from django.db import transaction
from django.utils import timezone
from .models import GroceryItem, GroceryActivity

logger = logging.getLogger(__name__)

# Unit conversion factors: (from_unit, to_unit) -> factor
UNIT_CONVERSIONS = {
    ('kg', 'g'): Decimal('1000'),
    ('g', 'kg'): Decimal('0.001'),
    ('l', 'ml'): Decimal('1000'),
    ('ml', 'l'): Decimal('0.001'),
    ('dozen', 'pcs'): Decimal('12'),
    ('pcs', 'dozen'): Decimal('0.083333'),
}

def convert_quantity(quantity: Decimal, from_unit: str, to_unit: str):
    """
    Converts quantity from one unit to another if compatible.
    Returns (converted_quantity, is_compatible).
    """
    f = (from_unit or '').strip().lower()
    t = (to_unit or '').strip().lower()
    if not f or not t or f == t:
        return quantity, True
    if (f, t) in UNIT_CONVERSIONS:
        return (quantity * UNIT_CONVERSIONS[(f, t)]).quantize(Decimal('0.01')), True
    return None, False

def deduct_pantry_items_bulk(user, items_to_deduct, activity_source='meal_log', allow_partial=False):
    """
    Deducts items from a user's pantry cleanly in a database transaction with row-level locks.
    Never silently over-deducts. Validates unit compatibility.
    `items_to_deduct`: List of dicts, e.g. [{'pantry_item_id': UUID/str, 'name': str, 'quantity': float, 'unit': str}]
    Returns (deducted_items_summary_list, errors_list)
    """
    summary = []
    errors = []

    with transaction.atomic():
        # First pass: validate existence, units, and stock sufficiency
        plan = []
        for item_data in items_to_deduct:
            pantry_item_id = item_data.get('pantry_item_id')
            item_name = item_data.get('name', 'Unknown Item')
            raw_qty = item_data.get('quantity', 0)
            req_unit = item_data.get('unit', '')

            try:
                requested_qty = Decimal(str(raw_qty))
            except (ValueError, TypeError):
                errors.append(f"Invalid quantity '{raw_qty}' for item '{item_name}'.")
                continue

            if requested_qty <= 0:
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
                errors.append(f"Item '{item_name}' not found or out of stock in kitchen.")
                continue

            # Check unit compatibility
            normalized_qty, compatible = convert_quantity(requested_qty, req_unit, grocery_item.unit)
            if not compatible:
                errors.append(
                    f"Incompatible unit '{req_unit}' for item '{grocery_item.name}' (stored in '{grocery_item.unit}')."
                )
                continue

            prev_quantity = grocery_item.quantity
            if normalized_qty > prev_quantity:
                # Business rule: Reject insufficient quantity; never silently set stock to 0
                errors.append(
                    f"Insufficient stock for '{grocery_item.name}': requested {normalized_qty} {grocery_item.unit}, "
                    f"but only {prev_quantity} {grocery_item.unit} available."
                )
                continue

            plan.append((grocery_item, normalized_qty, prev_quantity))

        # If there are errors and partial deduction is not allowed, rollback by raising or returning errors
        if errors and not allow_partial:
            return [], errors

        # Second pass: execute deductions
        for grocery_item, deduction_qty, prev_quantity in plan:
            new_quantity = prev_quantity - deduction_qty
            grocery_item.quantity = new_quantity
            grocery_item.save(update_fields=['quantity'])

            # Record activity
            GroceryActivity.objects.create(
                user=user,
                grocery_item=grocery_item if new_quantity > 0 else None,
                activity_type=GroceryActivity.ActivityTypes.CONSUMED,
                previous_quantity=prev_quantity,
                new_quantity=new_quantity,
                unit=grocery_item.unit,
                metadata={'source': activity_source, 'deducted_amount': float(deduction_qty)}
            )

            # Auto-add to grocery list if finished
            if new_quantity <= 0:
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

            # Update user stats
            effective_date = grocery_item.expiry_date or grocery_item.estimated_consumption_date
            if effective_date and effective_date >= timezone.now().date():
                user.saved_from_waste += 1
                user.save(update_fields=['saved_from_waste'])

            summary.append({
                'pantry_item_id': str(grocery_item.id),
                'name': grocery_item.name,
                'deducted_quantity': float(deduction_qty),
                'remaining_quantity': float(new_quantity),
                'unit': grocery_item.unit
            })

    return summary, errors
