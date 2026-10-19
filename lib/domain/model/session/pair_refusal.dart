/// Why presenting a pairing link did not let this device in.
///
/// Separate values rather than one failure, because each leads the person to a
/// different action, and collapsing them would force the app to invent wording
/// it does not know:
///
/// * [notUsable] — the link is spent or was never real. Get another one.
/// * [expired] — it was real and outlived its deadline: the link itself, or
///   the request an invite opened, which lives exactly as long. Ask for a new
///   one.
/// * [declined] — an invite whose request the person's own device that issued
///   it answered with Deny (phase 046). Nobody else is ever asked: this
///   machine belongs to one person, and every device on it is theirs.
enum PairRefusal { notUsable, expired, declined }
