from rest_framework import serializers

from .models import GroceryList, GroceryListItem


class GroceryListItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = GroceryListItem
        fields = '__all__'
        read_only_fields = ('id', 'grocery_list', 'created_at', 'updated_at')

class GroceryListSerializer(serializers.ModelSerializer):
    items = GroceryListItemSerializer(many=True, read_only=True)

    class Meta:
        model = GroceryList
        fields = ('id', 'status', 'generation_reason', 'created_at', 'updated_at', 'items')
        read_only_fields = ('id', 'created_at', 'updated_at')
class GroceryListItemCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = GroceryListItem
        fields = ('name', 'quantity', 'unit', 'reason', 'confidence')
