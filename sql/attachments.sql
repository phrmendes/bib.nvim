-- Get attachments (PDFs) for a specific item by its key
-- Returns path, contentType, and the attachment item's own key for storage resolution
-- Parameter: :key
SELECT itemAttachments.path, itemAttachments.contentType, attachKeys.key AS attachKey
FROM itemAttachments
JOIN items ON itemAttachments.parentItemID = items.itemID
JOIN items AS attachKeys ON itemAttachments.itemID = attachKeys.itemID
WHERE items.key = :key AND itemAttachments.contentType = 'application/pdf'
