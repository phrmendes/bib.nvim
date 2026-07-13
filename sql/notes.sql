-- Get notes for a specific item by its itemID
-- Parameter: :itemID
SELECT note, title
FROM itemNotes
WHERE parentItemID = :itemID
