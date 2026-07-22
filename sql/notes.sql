-- Get notes for a specific item by its key
-- Parameter: :key
SELECT note, title
FROM itemNotes
JOIN items ON itemNotes.parentItemID = items.itemID
WHERE items.key = :key
