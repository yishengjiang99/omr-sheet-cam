% Ode to Joy (L. v. Beethoven, Symphony No. 9, public domain), simplified melody.
% Sample picture for the app's "Try sample picture" button.
% Render (LilyPond 2.24): lilypond -dresolution=180 --png ode-to-joy.ly  (1530x1980 letter page)
% then flatten on white, crop the empty bottom of the page (keep a margin of 8% of the width),
% and save as JPEG quality 90 -> ode-to-joy.jpg (1530x~1240).
\version "2.24.0"
#(set-global-staff-size 24)

\paper {
  #(set-paper-size "letter")
  indent = 0
  ragged-last = ##f
  system-system-spacing.basic-distance = #16
  markup-system-spacing.basic-distance = #14
  top-margin = 18\mm
  left-margin = 16\mm
  right-margin = 16\mm
}

\header {
  title = "Ode to Joy"
  composer = "L. v. Beethoven"
  tagline = ##f
}

melody = {
  \clef treble \key c \major \time 4/4
  e'4 e' f' g' | g' f' e' d' | c' c' d' e' | e'4. d'8 d'2 | \break
  e'4 e' f' g' | g' f' e' d' | c' c' d' e' | d'4. c'8 c'2 | \break
  d'4 d' e' c' | d' e' c'2 | d'4 e' d' c' | c'4 d' d'2 | \break
  e'4 e' f' g' | g' f' e' d' | c' c' d' e' | d'4. c'8 c'2 \bar "|."
}

\score {
  \new Staff \melody
  \layout { \context { \Score \remove "Bar_number_engraver" } }
}
