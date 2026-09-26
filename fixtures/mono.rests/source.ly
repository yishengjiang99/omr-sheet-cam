% SPDX-License-Identifier: CC0-1.0
% fixtures/mono.rests — quarter notes alternating with quarter rests
\version "2.24.0"
\include "../../tools/fixtures/common.ily"
\score {
  \new Staff {
    \clef treble \key c \major \time 4/4
    c'4 r4 e'4 r4 | g'4 r4 c''4 r4 \bar "|"
  }
  \layout { }
  \midi { }
}
