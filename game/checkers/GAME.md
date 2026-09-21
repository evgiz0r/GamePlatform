# checkers

> This is the design of ONE game, in the words of whoever is making it. The AI reads
> it before every change to this game and it outranks the AI's own taste. Bad
> handwriting is fine, so is changing your mind.

## What is it called?

checkers

## Who are you?

You are the bottom side of a checkers board, playing against the computer.

## What do you do?

**Simple checkers.** Tap a piece, tap where it goes. With the rule of must eat, eating
backwards and so on.

(Arrow keys also work: they steer a glowing cursor, space picks up and drops a piece.)

## What is trying to stop you?

The opponent is an AI in **3 difficulties**: easy, normal, hard. It moves quickly.

## How do you win?

Take every one of its pieces, or leave it with no move. Lose all of yours and it is over.
I can reset the game whenever I want. **No time**, no clock: think as long as you like.

## What should it look like?

A neon board on the dark screen. Your pieces in your colour, the computer's in the
hazard colour, kings with a crown mark.

## Core loop

> Pick a piece → see where it can go → move or jump → the computer answers at once →
> the board thins out until one side is gone.

## Notes

- **The rules** (Russian draughts, the common "must eat" family):
  - eight by eight, twelve pieces each, dark squares only, you move first;
  - a man moves one square diagonally forward and **captures forwards or backwards**;
  - a **capture is compulsory**, and a jump keeps going while it can ("and so on"), turning
    corners if it has to. When several captures are on offer you pick any one of them,
    but you must play the whole sequence out; a landing square from which the jump can
    continue has to be taken over one from which it cannot;
  - a man that reaches the far row becomes a **king**, mid-jump too, and carries on as one;
  - kings **fly**: any distance along a diagonal, and after a capture they may land on any
    empty square beyond the victim;
  - the pieces taken in one jump come off the board at the end of it, so the same piece
    cannot be jumped twice;
  - a side with no legal move loses. Thirty king moves in a row from both sides with no
    capture and no man moved is a draw, which counts as a game over.
- **Three difficulties**, switchable at any time from the buttons on the left, taking
  effect on the computer's next move:
  - **easy** looks one move ahead and adds a lot of noise, so it blunders;
  - **normal** looks three plies ahead with a little noise;
  - **hard** searches as deep as a quarter of a second allows (six plies from the
    opening, deeper as the board empties) with no noise. All three still obey must-eat,
    since the rules do.
- **The computer answers in well under half a second**: the search runs inside a
  time budget, then a short pause before the piece slides so the reply is readable.
- **Score**: ten a man, thirty a king, three hundred for the win, times one, two or three
  for easy, normal, hard. The computer taking your pieces costs nothing; losing ends the
  run and the shell keeps the high score.
- **Reset** rebuilds the board with the same difficulty and puts the score back to zero.
- Pieces that can capture wear a warning ring while capturing is compulsory, so "why
  can't I move this one?" answers itself. The computer's last move stays faintly lit.
- The kit's default sound is too loud, so checkers scales it to 0.28 of the setting
  while it is on screen and puts it back when you leave.
- **For playtests**: the cursor is the `@`, your pieces are `p`, the computer's are `o`
  (tagging them `x` makes the bot flee the whole board), and every square you may pick
  or move to right now is a `*`, so the `smart` bot actually plays: it walks the cursor
  to the nearest `*` and presses space. The report always warns that nothing hostile was
  tracked; that is expected. There is no clock in real play, so an idle player never
  loses; `CHECKERS_IDLE_SECONDS=8` in the environment makes a player who does nothing for
  that long resign, which is how the `idle` run gets its fail state. Bots cannot press
  the level buttons either, so `CHECKERS_LEVEL=hard` (or `easy`) picks the opponent for
  a run; the default is normal.

## Ideas for later

- Two humans on one screen
- Undo the last move
- A hint button that shows the computer's favourite move
- International (10x10) rules as an option
