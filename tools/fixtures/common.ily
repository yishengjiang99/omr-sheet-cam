% SPDX-License-Identifier: CC0-1.0
% Shared engraving settings for synthetic OMR fixtures (fixtures/<id>/source.ly).
% Clean single page, no title/tagline, numeric 4/4 (homr only encodes the
% time-signature denominator, so C vs 4/4 would both read timeSignature/4).
\version "2.24.0"
\header { tagline = ##f }
\paper {
  #(set-paper-size "a4")
  indent = 0\mm
  top-margin = 20\mm
}
\layout {
  \context { \Staff \numericTimeSignature }
}
