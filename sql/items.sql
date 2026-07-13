-- Get all items with their types and field values
-- Returns: itemID, key, typeName, fieldName, value
SELECT
  items.itemID,
  items.key,
  itemTypes.typeName,
  fields.fieldName,
  itemDataValues.value
FROM items
JOIN itemTypes
  ON items.itemTypeID = itemTypes.itemTypeID
JOIN itemData
  ON items.itemID = itemData.itemID
JOIN fields
  ON itemData.fieldID = fields.fieldID
JOIN itemDataValues
  ON itemData.valueID = itemDataValues.valueID
WHERE itemTypes.typeName NOT IN ('attachment', 'annotation', 'note')
