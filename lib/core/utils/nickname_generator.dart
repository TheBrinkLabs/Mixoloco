import 'dart:math';

const _adjectives = ['Zesty', 'Fizzy', 'Lucky', 'Salty', 'Sunny', 'Spicy', 'Frosty', 'Minty', 'Breezy', 'Shaken', 'Stirred', 'Golden', 'Tropic', 'Velvet', 'Cosmic', 'Smooth'];
const _nouns = ['Mojito', 'Lime', 'Cherry', 'Mango', 'Coconut', 'Shaker', 'Spritz', 'Colada', 'Martini', 'Lemon', 'Bellini', 'Punch', 'Peach', 'Melon', 'Julep', 'Fizz'];

/// A fun default nickname, e.g. "ZestyMojito42" (at most 17 characters,
/// under the 20 the rules allow). Every player gets one automatically with
/// their first score (see LeagueRepository.ensureProfileWithDefaultName)
/// and can change it from the Global tab or Settings.
String generateFallbackNickname() => _nameFrom(Random());

/// The same style of name, but always the same one for [uid] — shown for
/// a score whose player never got a profile (an older app version), so the
/// board shows distinct names rather than a column of "Player".
String nicknameForUid(String uid) => _nameFrom(Random(uid.codeUnits.fold<int>(17, (h, c) => (h * 31 + c) & 0x7fffffff)));

String _nameFrom(Random r) =>
    '${_adjectives[r.nextInt(_adjectives.length)]}${_nouns[r.nextInt(_nouns.length)]}${10 + r.nextInt(90)}';
