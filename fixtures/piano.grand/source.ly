% SPDX-License-Identifier: CC0-1.0
% fixtures/piano.grand — grand staff, 4 bars of C-E-G-C quarters per staff
% (treble C4 E4 G4 C5 over bass C3 E3 G3 C4)
\version "2.24.0"
\include "../../tools/fixtures/common.ily"
\score {
  \new PianoStaff <<
    \new Staff {
      \clef treble \key c \major \time 4/4
      \repeat unfold 4 { c'4 e'4 g'4 c''4 | } \bar "|"
    }
    \new Staff {
      \clef bass \key c \major \time 4/4
      \repeat unfold 4 { c4 e4 g4 c'4 | } \bar "|"
    }
  >>
  \layout { }
  \midi { }
}
