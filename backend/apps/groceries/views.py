from rest_framework import viewsets, status, filters
from rest_framework.response import Response
from rest_framework.decorators import action
from django.db import transaction
from django.utils import timezone
from django.db.models import Sum, Count
from .models import GroceryItem, GroceryActivity
from .serializers import GroceryItemSerializer
from common.exceptions import ResourceNotFoundException, ForbiddenException
import decimal

class GroceryItemViewSet(viewsets.ModelViewSet):
    serializer_class = GroceryItemSerializer
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ['name', 'brand', 'category']
    ordering_fields = ['expiry_date', 'created_at', 'quantity']
    ordering = ['expiry_date']

    def get_queryset(self):
        # Enforce IDOR protection by scoping querysets to request.user
        return GroceryItem.objects.filter(user=self.request.user).exclude(quantity=0)

    def perform_create(self, serializer):
        with transaction.atomic():
            item = serializer.save(user=self.request.user)
            # Record user activity
            GroceryActivity.objects.create(
                user=self.request.user,
                grocery_item=item,
                activity_type=GroceryActivity.ActivityTypes.ITEM_ADDED,
                new_quantity=item.quantity,
                unit=item.unit
            )
            # Increment user stats
            user = self.request.user
            user.total_tracked += 1
            user.save(update_fields=['total_tracked'])

    def perform_update(self, serializer):
        with transaction.atomic():
            old_qty = self.get_object().quantity
            item = serializer.save()
            new_qty = item.quantity
            
            activity_type = GroceryActivity.ActivityTypes.ITEM_UPDATED
            if old_qty != new_qty:
                activity_type = (
                    GroceryActivity.ActivityTypes.QUANTITY_INCREASED 
                    if new_qty > old_qty else GroceryActivity.ActivityTypes.QUANTITY_DECREASED
                )
            
            GroceryActivity.objects.create(
                user=self.request.user,
                grocery_item=item,
                activity_type=activity_type,
                previous_quantity=old_qty,
                new_quantity=new_qty,
                unit=item.unit
            )

    def perform_destroy(self, instance):
        with transaction.atomic():
            GroceryActivity.objects.create(
                user=self.request.user,
                grocery_item=None,
                activity_type=GroceryActivity.ActivityTypes.ITEM_DELETED,
                previous_quantity=instance.quantity,
                unit=instance.unit,
                metadata={'deleted_item_name': instance.name}
            )
            instance.delete()

    @action(detail=True, methods=['post'], url_path='adjust-quantity')
    def adjust_quantity(self, request, pk=None):
        item = self.get_object()
        adjustment = request.data.get('adjustment')
        if adjustment is None:
            return Response({"success": False, "error": "Adjustment field is required."}, status=400)
            
        try:
            adjustment_val = decimal.Decimal(str(adjustment))
        except (ValueError, TypeError):
            return Response({"success": False, "error": "Invalid decimal format."}, status=400)

        with transaction.atomic():
            # Refresh from database and row-lock to avoid lost updates
            item = GroceryItem.objects.select_for_update().get(pk=item.pk)
            old_qty = item.quantity
            new_qty = old_qty + adjustment_val
            
            if new_qty < 0:
                return Response({"success": False, "error": "Quantity cannot become negative."}, status=400)

            item.quantity = new_qty
            item.save()

            GroceryActivity.objects.create(
                user=self.request.user,
                grocery_item=item,
                activity_type=GroceryActivity.ActivityTypes.QUANTITY_CORRECTED,
                previous_quantity=old_qty,
                new_quantity=new_qty,
                unit=item.unit
            )
            
            return Response({
                "success": True,
                "data": GroceryItemSerializer(item).data,
                "message": f"Quantity updated to {new_qty}"
            })

    @action(detail=True, methods=['post'])
    def consume(self, request, pk=None):
        item = self.get_object()
        consume_qty = request.data.get('quantity')
        
        with transaction.atomic():
            item = GroceryItem.objects.select_for_update().get(pk=item.pk)
            old_qty = item.quantity
            
            if consume_qty is None:
                consume_val = old_qty
            else:
                try:
                    consume_val = decimal.Decimal(str(consume_qty))
                except (ValueError, TypeError):
                    return Response({"success": False, "error": "Invalid consume quantity format."}, status=400)

            if consume_val <= 0 or consume_val > old_qty:
                return Response({"success": False, "error": "Invalid consume quantity bounds."}, status=400)

            new_qty = old_qty - consume_val
            item.quantity = new_qty
            item.save()

            # Record consumed activity
            GroceryActivity.objects.create(
                user=self.request.user,
                grocery_item=item if new_qty > 0 else None,
                activity_type=GroceryActivity.ActivityTypes.CONSUMED,
                previous_quantity=old_qty,
                new_quantity=new_qty,
                unit=item.unit,
                metadata={'consumed_quantity': float(consume_val)}
            )

            # Auto-add to smart grocery list when item is finished (quantity == 0)
            if new_qty <= 0:
                try:
                    from apps.grocery_lists.services import add_to_active_grocery_list
                    add_to_active_grocery_list(
                        user=self.request.user,
                        name=item.name,
                        unit=item.unit,
                        quantity=1.0,
                        reason=f"Finished in your kitchen ({item.name}). Restock recommended.",
                        source_signal='item_finished'
                    )
                except Exception as e:
                    logger.warning(f"Could not auto-add finished item to grocery list: {e}")

            return Response({
                "success": True,
                "data": GroceryItemSerializer(item).data,
                "message": f"Successfully consumed {consume_val} {item.unit}"
            })

    @action(detail=True, methods=['post'])
    def waste(self, request, pk=None):
        item = self.get_object()
        waste_qty = request.data.get('quantity')
        
        with transaction.atomic():
            item = GroceryItem.objects.select_for_update().get(pk=item.pk)
            old_qty = item.quantity
            
            if waste_qty is None:
                waste_val = old_qty
            else:
                try:
                    waste_val = decimal.Decimal(str(waste_qty))
                except (ValueError, TypeError):
                    return Response({"success": False, "error": "Invalid waste quantity format."}, status=400)

            if waste_val <= 0 or waste_val > old_qty:
                return Response({"success": False, "error": "Invalid waste quantity bounds."}, status=400)

            new_qty = old_qty - waste_val
            item.quantity = new_qty
            item.save()

            # Auto-add to smart grocery list when item is depleted/wasted
            if new_qty <= 0:
                try:
                    from apps.grocery_lists.services import add_to_active_grocery_list
                    add_to_active_grocery_list(
                        user=self.request.user,
                        name=item.name,
                        unit=item.unit,
                        quantity=1.0,
                        reason=f"Depleted/wasted in kitchen ({item.name}). Restock recommended.",
                        source_signal='item_wasted'
                    )
                except Exception as e:
                    logger.warning(f"Could not auto-add wasted item to grocery list: {e}")

            # Update stats
            user = self.request.user
            user.saved_from_waste += 1
            user.save(update_fields=['saved_from_waste'])

            # Record wasted activity
            GroceryActivity.objects.create(
                user=self.request.user,
                grocery_item=item if new_qty > 0 else None,
                activity_type=GroceryActivity.ActivityTypes.WASTED,
                previous_quantity=old_qty,
                new_quantity=new_qty,
                unit=item.unit,
                metadata={'wasted_quantity': float(waste_val)}
            )

            return Response({
                "success": True,
                "data": GroceryItemSerializer(item).data,
                "message": f"Successfully recorded waste for {waste_val} {item.unit}"
            })

    @action(detail=False, methods=['get'], url_path='use-first')
    def use_first(self, request):
        # Fetch items close to expiry
        queryset = self.get_queryset().filter(expiry_date__isnull=False).order_by('expiry_date')[:5]
        serializer = GroceryItemSerializer(queryset, many=True)
        return Response({
            "success": True,
            "data": serializer.data
        })

    @action(detail=False, methods=['get'])
    def stats(self, request):
        queryset = self.get_queryset()
        total = queryset.count()
        fresh = queryset.filter(status='fresh').count()
        expiring = queryset.filter(status='expiring').count()
        expired = queryset.filter(status='expired').count()
        
        return Response({
            "success": True,
            "data": {
                "fresh": fresh,
                "expiring": expiring,
                "expired": expired,
                "total": total
            }
        })

    @action(detail=False, methods=['get'])
    def zones(self, request):
        queryset = self.get_queryset()
        # Group counts by storage zones
        zones_counts = queryset.values('storage_zone').annotate(count=Count('id'))
        
        data = {zone[0]: 0 for zone in GroceryItem.StorageZones.choices}
        for item in zones_counts:
            data[item['storage_zone']] = item['count']

        return Response({
            "success": True,
            "data": data
        })

    @action(detail=False, methods=['post'], url_path='predict-shelf-life')
    def predict_shelf_life(self, request):
        data = request.data
        from .prediction_engine import ShelfLifePredictionEngine
        prediction = ShelfLifePredictionEngine.predict(data)
        
        # Serialize dates to string
        prediction['predicted_expiry'] = prediction['predicted_expiry'].isoformat()
        prediction['recommended_consumption_date'] = prediction['recommended_consumption_date'].isoformat()
        
        return Response({
            "success": True,
            "data": prediction
        })

    @action(detail=False, methods=['get'], url_path='barcode-lookup')
    def barcode_lookup(self, request):
        barcode = request.query_params.get('barcode', '').strip()
        if not barcode:
            return Response(
                {"success": False, "error": "Barcode parameter is required."},
                status=status.HTTP_400_BAD_REQUEST
            )

        # 1. Check user's pantry history
        pantry_item = GroceryItem.objects.filter(
            user=request.user,
            barcode=barcode
        ).order_by('-created_at').first()

        if pantry_item:
            return Response({
                "success": True,
                "data": {
                    "barcode": barcode,
                    "name": pantry_item.name,
                    "brand": pantry_item.brand,
                    "category": pantry_item.category,
                    "unit": pantry_item.unit,
                    "calories_per_100g": pantry_item.calories_per_100g,
                    "allergens": pantry_item.allergens if isinstance(pantry_item.allergens, list) else [],
                    "storage_zone": pantry_item.storage_zone,
                    "source": "pantry_history",
                    "found": True,
                }
            })

        # 2. Query Open Food Facts
        from .barcode_lookup import lookup_open_food_facts
        off_product = lookup_open_food_facts(barcode)
        if off_product:
            return Response({
                "success": True,
                "data": off_product
            })

        # 3. Not found fallback
        return Response({
            "success": True,
            "data": {
                "barcode": barcode,
                "found": False,
            },
            "message": "No product found for this barcode. Please enter details manually."
        }, status=status.HTTP_200_OK)


    @action(detail=False, methods=['get'], url_path='ai-insights')
    def ai_insights(self, request):
        user = request.user
        # Single efficient database query fetching only required fields
        items = list(
            GroceryItem.objects.filter(user=user)
            .exclude(quantity=0)
            .only('name', 'status', 'category', 'freshness_score')
        )
        
        insights = []
        
        # In-memory partitioning to eliminate 8+ redundant DB network queries
        expiring_items = [item for item in items if item.status == 'expiring']
        expired_items = [item for item in items if item.status == 'expired']
        categories = {item.category.lower() for item in items if item.category}
        
        # 1. Check expiring soon
        if expiring_items:
            names = [item.name for item in expiring_items[:3]]
            if len(expiring_items) > 3:
                insights.append(f"You have {len(expiring_items)} items expiring soon, including {', '.join(names)}, and others.")
            else:
                insights.append(f"You have items expiring soon: {', '.join(names)}.")
        
        # 2. Check expired
        if expired_items:
            insights.append(f"Warning: {len(expired_items)} items have already expired. Please clear them out to keep your kitchen clean.")
        
        # 3. Dynamic conservation advice
        if 'fruits' in categories or 'fruit' in categories:
            insights.append("Keeping bananas separate from other fruits prevents ethylene gas from ripening them too quickly.")
        if 'vegetables' in categories or 'vegetable' in categories:
            insights.append("Store leafy greens with a paper towel inside a sealed bag in the crisper drawer to absorb excess moisture.")
        if 'dairy' in categories:
            insights.append("Avoid storing milk in the refrigerator door; temperature fluctuations there accelerate spoilage.")

        # 4. Wastage estimate
        total_expiring = len(expiring_items)
        estimated_waste_value = total_expiring * 65  # Mock ₹65 per expiring item
        if estimated_waste_value > 0:
            insights.append(f"You may waste ₹{estimated_waste_value} worth of groceries this week if they are not consumed.")

        if not insights:
            insights = [
                "Your pantry is in healthy shape! Keep logging items to receive personalized shelf life predictions.",
                "Storage temperature control is the easiest way to prevent grocery wastage.",
                "Planning meals around your expiring list saves money and reduces waste."
            ]

        if items:
            freshness_score = int(sum(item.freshness_score for item in items) / len(items))
        else:
            freshness_score = 100

        return Response({
            "success": True,
            "data": {
                "insights": insights,
                "waste_risk": estimated_waste_value,
                "freshness_score": freshness_score
            }
        })
