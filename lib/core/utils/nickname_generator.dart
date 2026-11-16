import 'dart:math';

/// Longest nickname allowed — fits the Global board's name column at full
/// size. (firestore.rules still allow 20, so names saved before this
/// limit keep working; the board shrinks those to fit.)
const kMaxNicknameLength = 12;

// Five letters at most each, so adjective + noun + two digits <= 12.
const _adjectives = ['Zesty', 'Fizzy', 'Lucky', 'Salty', 'Sunny', 'Spicy', 'Minty', 'Juicy', 'Tangy', 'Sweet', 'Icy', 'Cool', 'Wild', 'Sour', 'Hot', 'Bold'];
const _nouns = ['Lime', 'Mango', 'Peach', 'Lemon', 'Melon', 'Fizz', 'Punch', 'Julep', 'Mint', 'Kiwi', 'Berry', 'Olive', 'Cola', 'Mojo', 'Shake', 'Sip'];

/// A fun default nickname, e.g. "ZestyMango42" — every new player is
/// offered one on first launch (see NicknameSetupScreen) and can keep it
/// or type their own.
String generateFallbackNickname() => _nameFrom(Random());

/// The same style of name, but always the same one for [uid] — shown for
/// a score whose player never got a profile (an older app version), so the
/// board shows distinct names rather than a column of "Player".
String nicknameForUid(String uid) => _nameFrom(Random(uid.codeUnits.fold<int>(17, (h, c) => (h * 31 + c) & 0x7fffffff)));

String _nameFrom(Random r) =>
    '${_adjectives[r.nextInt(_adjectives.length)]}${_nouns[r.nextInt(_nouns.length)]}${10 + r.nextInt(90)}';
