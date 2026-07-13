-- Get creators for all items
-- Returns: itemID, creatorType, lastName, firstName
SELECT
  items.itemID,
  creatorTypes.creatorType,
  creators.lastName,
  creators.firstName
FROM items
JOIN itemCreators
  ON items.itemID = itemCreators.itemID
JOIN creators
  ON itemCreators.creatorID = creators.creatorID
JOIN creatorTypes
  ON itemCreators.creatorTypeID = creatorTypes.creatorTypeID
