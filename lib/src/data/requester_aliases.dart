/// The names under which one person requested songs: the table of the requesters to recombine.
///
/// Pure Dart. The sheets name one person under several names: typos of the moderators who fill them, renamed or
/// second accounts. The names of one line of [requesterAliasTable] are one requester everywhere (see
/// [RequesterAliases]).
library;

import 'text.dart';

/// The groups of names of one person, one group per line, its names separated by commas, in any order; blank lines
/// are ignored. Names are compared folded (`fold`: case and accents do not matter), as the requesters of the sheets
/// are. The name shown for a group is not chosen here: it is the most written of its spellings in the sheets.
///
/// A name belongs to one group at most (the tests check it). A name in no group is a requester of its own, as before.
const requesterAliasTable = r'''
COREYT0WNS, COREYTOWNZ, COREYTOWNS, COREYTOWN, COREY T OWNS, coreyt, COREYT0WN, coreytownss, coreytow, COREYT0WNZ, COREYT0WNS0, COREYCLOWNS, COREYBROWNS, CORATOWNS, COREYCLOWN, CURRYTOWNS, SnoreyTowns, CORNEYTOWNS, corey t pwns, COREYCITIES, QUARRYTOWNS, CLOWNYTOWNS, CORGITOWNS, TOREYCOWNS, CORACLOWNS, COREYFROWNS, COREYYAWNS, corkeytowns, SPICY CURRYTOWNS, TOW N SCORE, Unicorny Towns, COREYPWNS, CORINATOWNS, COREYCROWNS, COREYTRONS, GLORYTOWNS, COREYCLOWNING, COREYTOES
thedarkmockrises, tdmr
jsbach64, jsbach, jsback64
slithycode, sithycode
katmatwo, Katamtwo, kamatwo
Votre_Pseudo, Votre Pseudo, Votre_Psuedo, Votre_Pseuido
Domineek_, Domineek
FreelancePhilosopher, FreelancePhilosopherPony, Freelance Philosopher, FreelancePhilospher
Tritiumo, Tritium o, Tritiiumo, Tritimo, Tritium
Taran858, taran85888888888888888888
MannyHub, manyhub, Mannyhubbityhub, Maaaaaaaaaaaaaaaanny, Manny
LordFloofen, LordFlofen
andviceversa_, stickyviceversa, andviceversa, andviceversaa, Stickyviceversa_, andviceverca_, adviceversa_, andvicecersa, anddviceversa_
bebop743, bebp743
ameliorates, amelorates
NiamorEllievel, NiamoEllievel
RobAncalagon, robancalgon
Fellgnoll, Fellngoll, fellgnol
Amodit, Armodit
Axiom42, axion42, Axionm42
yummi__butter, yummi_butter
Kirby_Bitera, KirbyBitera
w_a_t_c_h_, w_a_t_c_h, s_a_t_c_h
PrimroseLane, PrimeroseLane
FacelessWhisper, Faceless Whisper
Abe_pianoman, Abe_painoman
Time_relapse, Time_relaspe
KDLynch, kd_lynch
JonathanOng, Jonathan Ong
robxarghteim, Robxarg, Robxargteim, Robaxrghteim
corruppteddatastring, corRupPtedData, corRupPtedData$, corrupteddatastring, corruppteddatasstring
errraare, erraare, dee_errraare_836_phx, errrare
jtvetabick, jtvetabck
AussieDingbat, AusieDingbat
Blue_note__, Blue_note
BorisAmmerlaan, BorisAmmeriaan
DarthGaddy, Darth_Gaddy
Sarahhulkum, Sarah Hulkum
JohannGambolputtyOfUlm, JohannGambolpttyOfUlm
vU_Vu, vU_Uv
Oxizealot, Oxiezealot
maearr, maerr
stickyfredversa, stickeyfredversa
Fekctus, Fektus
CairnsByTheSea, CainsByTheSea
FGurskiMusic, FGurskyMusic
desert_pidgeon_, desert_pidgeon
laughing_psychonaut, LaughingPsychonaut
SIappyWhite64, SlappyWhite64
ThatBa5tardChap, ThatBa5stardChap
peanutshells85, peanutshell85
TCGJoe, TCGJoes
wavedavedash, wavedeavedash
Just_Peach, Just__Peach
supiriority_complex, superiority_complex
JeNoValcHiGo, JeNoVaIcHiGo
kizzak, kizzzak
Long_Dog, Long Dog
PizzaEyes, PizzaEyez
ShinTsu, Shin_Tsu
albinonounou, albinounounou
carboard_cowboy, CardBoardCowboy
helinefey, HelineFay
klynkmonky, klynkymonky
MistPocketLint, MoistPocketLint
combusterf, Combuster
legomanz88, legomanz
InTheShad0ws, InTheShadows
valxa__, valxa, Valxa_
Cherilyn1701, Cherilyn42, Cherilyn
mxstake2, mxTake2
ClusterHughie, Cluster
SisterGotGame222, SisterGotGame
Jackseltje, Jacksel
de_music, mike_de_music
Leland, Leland_Iko_Music
Jazsta22, Jazsta
Horsekel06, Horsekel
''';

/// The groups of names of [table] (see [requesterAliasTable]), as written: one list per line that is not blank.
List<List<String>> requesterAliasGroups(String table) => [
  for (final line in table.split('\n'))
    if (line.trim().isNotEmpty) [for (final name in line.split(',')) name.trim()],
];

/// The groups of names of one person, by folded name: [keyOf] gives the key of a requester (`Requester.folded`),
/// [searchTextOf] what a search looks for in their name.
///
/// The key of a group is the smallest of the folded names of its line: it depends neither on the order of the line
/// nor on the sheets, so that it stays the same when a refresh shows the group under another name.
final class RequesterAliases {
  /// The groups of [groups], each a list of names as written.
  RequesterAliases(List<List<String>> groups) {
    for (final group in groups) {
      final folds = {for (final name in group) fold(name)}.toList()..sort();
      if (folds.length < 2) continue;
      for (final f in folds) {
        // a name in two groups would join them, or leave the name in the search text of a group it is not of: the
        // tests of the table refuse it, and a hand edit that slips past them stops here in debug builds
        assert(!_keys.containsKey(f), 'the name "$f" is in two groups of the table of the requesters');
        _keys[f] = folds.first;
      }
      _searchTexts[folds.first] = folds.join('\n');
    }
  }

  /// The groups of [requesterAliasTable], those of the app.
  static final bundled = RequesterAliases(requesterAliasGroups(requesterAliasTable));

  /// No group: every name is a requester of its own.
  static final none = RequesterAliases(const []);

  final Map<String, String> _keys = {};
  final Map<String, String> _searchTexts = {};

  /// The key of the requester whose folded name is [folded]: the key of its group, or [folded] itself.
  String keyOf(String folded) => _keys[folded] ?? folded;

  /// Whether [key] ([keyOf]) is that of a group of several names.
  bool isGroup(String key) => _searchTexts.containsKey(key);

  /// What a search looks for in the names of the requester of key [key] ([keyOf]): the folded names of its group,
  /// one per line (a query token never holds a line break, so never spans two names), or [key] itself.
  String searchTextOf(String key) => _searchTexts[key] ?? key;
}
