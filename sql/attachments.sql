-- Get attachments (PDFs) for a specific item by its itemID
-- Parameter: :itemID
SELECT path, contentType
FROM itemAttachments
WHERE parentItemID = :itemID AND contentType = 'application/pdf'
