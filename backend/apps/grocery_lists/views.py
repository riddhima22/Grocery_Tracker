import logging

from django.db import transaction
from django.db.models import Count
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from apps.groceries.models import GroceryActivity, GroceryItem
from apps.groceries.serializers import GroceryItemSerializer
from common.exceptions import ResourceNotFoundException

from .models import GroceryList, GroceryListItem
from .serializers import (
    GroceryListItemCreateSerializer,
    GroceryListItemSerializer,
    GroceryListSerializer,
)

logger = logging.getLogger('freshtrack.grocery_lists')

class GroceryListViewSet(viewsets.ModelViewSet):
    serializer_class = GroceryListSerializer

    def get_queryset(self):
        # IDOR protection: scoped to request.user
        return GroceryList.objects.filter(user=self.request.user)

    @action(detail=False, methods=['get'])
    def current(self, request):
        user = request.user
        # Find active list or create a blank one
        list_obj = GroceryList.objects.filter(user=user, status=GroceryList.Statuses.ACTIVE).first()
        if not list_obj:
            list_obj = GroceryList.objects.create(
                user=user,
                status=GroceryList.Statuses.ACTIVE,
                generation_reason="Initial manual list"
            )
        serializer = GroceryListSerializer(list_obj)
        return Response({
            "success": True,
            "data": serializer.data
        })

    @action(detail=False, methods=['post'])
    def generate(self, request):
        user = request.user
        from decimal import Decimal

        # 1. Get or create the active grocery list (Preserve existing active items!)
        active_list = GroceryList.objects.filter(
            user=user,
            status=GroceryList.Statuses.ACTIVE
        ).order_by('-created_at').first()
        if not active_list:
            active_list = GroceryList.objects.create(
                user=user,
                status=GroceryList.Statuses.ACTIVE,
                generation_reason='Smart replenishment analysis'
            )

        existing_names = set(
            GroceryListItem.objects.filter(grocery_list=active_list, purchased=False)
            .values_list('name', flat=True)
        )
        existing_names_lower = {n.lower().strip() for n in existing_names if n}

        suggestions_added = 0

        with transaction.atomic():
            # Source 1: Items in kitchen that are finished (quantity <= 0)
            finished_items = GroceryItem.objects.filter(user=user, quantity__lte=0).order_by('-updated_at')[:10]
            for fi in finished_items:
                clean_name = fi.name.strip()
                if clean_name.lower() not in existing_names_lower:
                    GroceryListItem.objects.create(
                        grocery_list=active_list,
                        name=clean_name,
                        suggested_quantity=Decimal('1.0'),
                        quantity=Decimal('1.0'),
                        unit=fi.unit or 'pcs',
                        reason=f"Finished in kitchen ({clean_name}). Added for replenishment.",
                        confidence='High',
                        source_signal='finished_pantry_item',
                        feedback=GroceryListItem.Feedbacks.PENDING
                    )
                    existing_names_lower.add(clean_name.lower())
                    suggestions_added += 1

            # Source 2: Items in kitchen running low (0 < quantity <= 1 or status == 'expiring_soon')
            low_stock_items = GroceryItem.objects.filter(
                user=user,
                quantity__gt=0,
                quantity__lte=1
            ).order_by('expiry_date')[:8]
            for li in low_stock_items:
                clean_name = li.name.strip()
                if clean_name.lower() not in existing_names_lower:
                    GroceryListItem.objects.create(
                        grocery_list=active_list,
                        name=clean_name,
                        suggested_quantity=Decimal('1.0'),
                        quantity=Decimal('1.0'),
                        unit=li.unit or 'pcs',
                        reason=f"Low stock in kitchen ({li.quantity} {li.unit} remaining).",
                        confidence='Medium',
                        source_signal='low_stock_pantry_item',
                        feedback=GroceryListItem.Feedbacks.PENDING
                    )
                    existing_names_lower.add(clean_name.lower())
                    suggestions_added += 1

            # Source 3: Frequently consumed items from activity history
            activities = GroceryActivity.objects.filter(user=user)
            if activities.exists():
                top_items = activities.values('grocery_item__name', 'unit').annotate(
                    count=Count('id')
                ).order_by('-count')[:5]

                for item_info in top_items:
                    name = (item_info.get('grocery_item__name') or '').strip()
                    unit = item_info.get('unit') or 'pcs'
                    if name and name.lower() not in existing_names_lower:
                        # Only suggest if not already heavily stocked
                        in_stock = GroceryItem.objects.filter(
                            user=user, name__iexact=name, quantity__gt=1
                        ).exists()
                        if not in_stock:
                            GroceryListItem.objects.create(
                                grocery_list=active_list,
                                name=name,
                                suggested_quantity=Decimal('1.0'),
                                quantity=Decimal('1.0'),
                                unit=unit,
                                reason=f"You frequently consume {name}.",
                                confidence='High',
                                source_signal='frequent_usage',
                                feedback=GroceryListItem.Feedbacks.PENDING
                            )
                            existing_names_lower.add(name.lower())
                            suggestions_added += 1

            # Source 4: If list is still completely empty, suggest common kitchen essentials
            if active_list.items.filter(purchased=False).count() == 0:
                essentials = [
                    ('Fresh Milk', '1.0', 'L', 'Kitchen staple replenishment'),
                    ('Eggs', '6.0', 'pcs', 'High-protein breakfast staple'),
                    ('Bread', '1.0', 'pack', 'Breakfast staple'),
                    ('Tomatoes', '1.0', 'kg', 'Cooking essential'),
                    ('Onions', '1.0', 'kg', 'Cooking essential'),
                ]
                for name, qty, unit, reason in essentials:
                    GroceryListItem.objects.create(
                        grocery_list=active_list,
                        name=name,
                        suggested_quantity=Decimal(qty),
                        quantity=Decimal(qty),
                        unit=unit,
                        reason=reason,
                        confidence='Medium',
                        source_signal='kitchen_essential',
                        feedback=GroceryListItem.Feedbacks.PENDING
                    )
                    suggestions_added += 1

            active_list.refresh_from_db()

        serializer = GroceryListSerializer(active_list)
        return Response({
            "success": True,
            "data": serializer.data,
            "message": f"Smart grocery list updated with {suggestions_added} smart suggestions."
        })

    @action(detail=True, methods=['post'], url_path='items')
    def add_item(self, request, pk=None):
        list_obj = self.get_object()
        serializer = GroceryListItemCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        with transaction.atomic():
            item = GroceryListItem.objects.create(
                grocery_list=list_obj,
                name=serializer.validated_data['name'],
                suggested_quantity=serializer.validated_data.get('quantity', 1.0),
                quantity=serializer.validated_data.get('quantity', 1.0),
                unit=serializer.validated_data.get('unit', 'pcs'),
                reason="Added manually",
                confidence="High",
                feedback=GroceryListItem.Feedbacks.ACCEPTED
            )
            return Response({
                "success": True,
                "data": GroceryListItemSerializer(item).data,
                "message": f"Added {item.name} to grocery list."
            }, status=201)

    @action(detail=True, methods=['PATCH', 'DELETE'], url_path='items/(?P<item_pk>[^/.]+)')
    def manage_item(self, request, pk=None, item_pk=None):
        list_obj = self.get_object()
        try:
            item = list_obj.items.get(id=item_pk)
        except GroceryListItem.DoesNotExist:
            raise ResourceNotFoundException("Item not found in grocery list.")

        if request.method == 'DELETE':
            item.delete()
            return Response({
                "success": True,
                "data": {},
                "message": "Item removed from grocery list."
            })

        old_qty = item.quantity
        serializer = GroceryListItemSerializer(item, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        updated_item = serializer.save()

        # Update feedback automatically if quantity edited
        if old_qty != updated_item.quantity and updated_item.feedback == GroceryListItem.Feedbacks.PENDING:
            updated_item.feedback = GroceryListItem.Feedbacks.EDITED
            updated_item.save(update_fields=['feedback'])

        return Response({
            "success": True,
            "data": GroceryListItemSerializer(updated_item).data,
            "message": "Item updated successfully."
        })

    @action(detail=True, methods=['post'], url_path='items/(?P<item_pk>[^/.]+)/feedback')
    def set_feedback(self, request, pk=None, item_pk=None):
        list_obj = self.get_object()
        try:
            item = list_obj.items.get(id=item_pk)
        except GroceryListItem.DoesNotExist:
            raise ResourceNotFoundException("Item not found in grocery list.")

        feedback_val = request.data.get('feedback')
        if feedback_val not in GroceryListItem.Feedbacks.values:
            return Response({"success": False, "error": "Invalid feedback type."}, status=400)

        item.feedback = feedback_val
        item.save(update_fields=['feedback'])
        return Response({
            "success": True,
            "data": GroceryListItemSerializer(item).data,
            "message": f"Feedback updated to {feedback_val}"
        })

    @action(detail=True, methods=['post'], url_path='items/(?P<item_pk>[^/.]+)/mark-purchased')
    def mark_purchased(self, request, pk=None, item_pk=None):
        list_obj = self.get_object()
        try:
            item = list_obj.items.get(id=item_pk)
        except GroceryListItem.DoesNotExist:
            raise ResourceNotFoundException("Item not found in grocery list.")

        if item.purchased:
            return Response({"success": False, "error": "Item is already marked purchased."}, status=400)

        with transaction.atomic():
            item.purchased = True
            item.feedback = GroceryListItem.Feedbacks.ACCEPTED
            item.save()

            # Insert into pantry
            pantry_item = GroceryItem.objects.create(
                user=request.user,
                name=item.name,
                quantity=item.quantity,
                unit=item.unit,
                storage_zone='pantry' # default
            )

            # Record Activity
            GroceryActivity.objects.create(
                user=request.user,
                grocery_item=pantry_item,
                activity_type=GroceryActivity.ActivityTypes.ITEM_ADDED,
                new_quantity=pantry_item.quantity,
                unit=pantry_item.unit,
                metadata={'source': 'grocery_list'}
            )

            # Update stats
            user = request.user
            user.total_tracked += 1
            user.save(update_fields=['total_tracked'])

        return Response({
            "success": True,
            "data": GroceryItemSerializer(pantry_item).data,
            "message": f"Successfully purchased {item.name} and added to kitchen."
        })
