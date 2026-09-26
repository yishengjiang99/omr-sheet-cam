% SPDX-License-Identifier: CC0-1.0
% fixtures/clefs.bass — bass clef C3..C4 quarters
\version "2.24.0"
\include "../../tools/fixtures/common.ily"
\score {
  \new Staff {
    \clef bass \key c \major \time 4/4
    c4 d4 e4 f4 | g4 a4 b4 c'4 \bar "|"
  }
  \layout { }
  \midi { }
}
