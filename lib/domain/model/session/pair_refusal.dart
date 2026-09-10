/// Why presenting a pairing link did not let this device in.
///
/// Two values rather than one failure, because each leads the person to a
/// different action, and collapsing them would force the app to invent wording
/// it does not know:
///
/// * [notUsable] — the link is spent or was never real. Get another one.
/// * [expired] — it was real and outlived its deadline. Ask for a new one.
///
/// There used to be two more, for an invite that waited on another human being.
/// Pairing always finishes now: this machine belongs to one person, and the
/// only links it hands out are its own claim and an invite for another of that
/// person's devices.
enum PairRefusal { notUsable, expired }
