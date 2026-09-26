% SPDX-License-Identifier: CC0-1.0
% fixtures/poly.chord — single C4+E4+G4 quarter chord, then a barline.
% Written as a one-beat \partial (anacrusis) so the 4/4 bar is legal and the
% token GT (clef, time, chord, barline) is unchanged.
\version "2.24.0"
\include "../../tools/fixtures/common.ily"
\score {
  \new Staff {
    \clef treble \key c \major \time 4/4
    \partial 4 <c' e' g'>4 \bar "|"
  }
  \layout { ragged-right = ##t }
  \midi { }
}
