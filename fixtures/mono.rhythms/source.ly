% SPDX-License-Identifier: CC0-1.0
% fixtures/mono.rhythms — whole / half / quarter / 8th / 16th / dotted quarter
% (matches expected.notes.csv; default LilyPond 4/4 auto-beaming)
\version "2.24.0"
\include "../../tools/fixtures/common.ily"
\score {
  \new Staff {
    \clef treble \key c \major \time 4/4
    c'1 | d'2 e'2 | f'4 g'4 a'8 b'8 c''16 c''16 b'16 a'16 | g'4. f'8 e'2 \bar "|"
  }
  \layout { }
  \midi { }
}
