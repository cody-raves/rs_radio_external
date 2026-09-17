-- Integration contract version.
--
-- This must match the API level rs_radio reports. A mismatch means the two
-- resources disagree about the shape of the session payloads, so this resource
-- declines to attach rather than sending data the base may misread. The base
-- keeps running as a local-file radio either way.

RSRadioExternalContract = {
    -- Bump only when the payloads exchanged with the base change shape.
    requiredApi = 1,
    resourceName = "rs_radio_external"
}

function RSRadioExternalBaseResource()
    return "rs_radio"
end
