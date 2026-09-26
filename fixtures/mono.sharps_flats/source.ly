% SPDX-License-Identifier: CC0-1.0
% fixtures/mono.sharps_flats — C D E F# | G Ab B C quarters (matches expected.notes.csv)
\version "2.24.0"
\include "../../tools/fixtures/common.ily"
\score {
  \new Staff {
    \clef treble \key c \major \time 4/4
    c'4 d'4 e'4 fis'4 | g'4 aes'4 b'4 c''4 \bar "|"
  }
  \layout { }
  \midi { }
}
