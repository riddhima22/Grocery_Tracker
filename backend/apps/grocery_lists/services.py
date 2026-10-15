import logging
from decimal import Decimal
from .models import GroceryList, GroceryListItem

logger = logging.getLogger('freshtrack.grocery_lists')


def add_to_active_grocery_list(
    user,
    name: str,
    unit: str = 'pcs',
    quantity: float = 1.0,
    reason: str = 'Finished in kitchen. Added for replenishment.',
    confidence: str = 'High',
    source_signal: str = 'item_finished'
):
    """
    Safely adds or restocks an item in the user's active GroceryList.
    Avoids duplicate entries if the item is already pending in the active list.
    If it was previously marked purchased, resets purchased to False for restock.
    """
    name = (name or '').strip()
    if not name:
        return None

    try:
        # 1. Get or create the user's active grocery list
        active_list = GroceryList.objects.filter(
            user=user,
            status=GroceryList.Statuses.ACTIVE
        ).order_by('-created_at').first()
        if not active_list:
            active_list = GroceryList.objects.create(
                user=user,
                status=GroceryList.Statuses.ACTIVE,
                generation_reason='Smart replenishment'
            )

        # 2. Check if item already exists in the active list
        existing = GroceryListItem.objects.filter(
            grocery_list=active_list,
            name__iexact=name
        ).first()

        if existing:
            # If already purchased, unmark so user can buy again
            if existing.purchased:
                existing.purchased = False
                existing.quantity = max(existing.quantity, Decimal(str(quantity)))
                existing.reason = reason
                existing.feedback = GroceryListItem.Feedbacks.PENDING
                existing.save(update_fields=['purchased', 'quantity', 'reason', 'feedback', 'updated_at'])
            return existing

        # 3. Create new replenishment item
        item = GroceryListItem.objects.create(
            grocery_list=active_list,
            name=name,
            suggested_quantity=Decimal(str(quantity)),
            quantity=Decimal(str(quantity)),
            unit=unit or 'pcs',
            reason=reason,
            confidence=confidence,
            source_signal=source_signal,
            feedback=GroceryListItem.Feedbacks.PENDING,
            purchased=False
        )
        logger.info(f"Auto-added '{name}' ({quantity} {unit}) to active grocery list for user {user.email}")
        return item
    except Exception as e:
        logger.error(f"Failed to auto-add '{name}' to grocery list: {e}", exc_info=True)
        return None
