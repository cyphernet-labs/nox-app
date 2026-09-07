/// Why presenting a pairing link did not let somebody in.
///
/// Four values rather than one failure, because each leads the person to a
/// different action, and collapsing them would force the app to invent wording
/// it does not know:
///
/// * [notUsable] — the link is spent or was never real. Get another one.
/// * [expired] — it was real and outlived its deadline. Ask for a new one.
/// * [declined] — the owner said no. Do not insist.
/// * [noAnswer] — the owner never answered. Ask again.
///
/// The last two exist only for invites to a new PERSON (contract §8B): a device
/// invite and a claim finish immediately and never wait on anybody.
enum PairRefusal { notUsable, expired, declined, noAnswer }
