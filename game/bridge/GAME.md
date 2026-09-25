# bridge

> This is the design of ONE game, in the words of whoever is making it. The AI reads
> it before every change to this game and it outranks the AI's own taste. Bad
> handwriting is fine, so is changing your mind.

## What is it called?

bridge

## Who are you?

You sit south. **Me + AI vs AI + AI**: the computer is your partner (north) and both
opponents (west and east).

## What do you do?

Classic bridge, **the most classic variant**: contract bridge scored as **rubber
bridge**. Bid on the bidding box, then tap cards to play them.

## What is trying to stop you?

Two computer opponents, in **3 levels of difficulty**: easy, normal, hard.

## How do you win?

Win the rubber: the first side to make two games. At the end, whoever has more points
on the scoresheet wins.

## What should it look like?

A neon card table on the dark screen. A four-colour deck (spades, hearts, diamonds and
clubs each in their own palette colour) so suits read at a glance on a phone.

## Core loop

> Look at thirteen cards -> bid with partner to a contract -> play it out a trick at a
> time -> score it -> the next deal, until one side has two games.

## Notes

- **The rules**: standard contract bridge. Four hands of thirteen, the deal and the first
  call go round clockwise, calls are bids from 1C to 7NT, double and redouble, and three
  passes after a bid end the auction (four passes: thrown in and redealt). The first
  player of the winning side to name the final strain declares; the hand on declarer's
  left leads, then dummy goes face up. Follow suit if you can, trumps win, the winner of
  a trick leads the next.
- **Who plays what**: when your side wins the contract you play both hands, yours and
  north's, whichever of you is declarer, as a declarer does. When the opponents declare
  you defend with your own hand and the computer partner defends with its own.
- **Rubber scoring**: tricks bid and made go below the line (clubs and diamonds 20,
  hearts and spades 30, no trumps 40 then 30, times two or four when doubled or
  redoubled); 100 below the line is a game and wipes both part-scores. Overtricks,
  undertricks, slam bonuses (500/750, 1000/1500), the 50/100 for making a doubled or
  redoubled contract, honours (100 for four trump honours in one hand, 150 for all five
  or all four aces at no trumps) and the rubber bonus (700 for two games to none, 500
  for two to one) go above. A side with a game is vulnerable, and pays and earns more.
- **The bidding system** every computer seat bids, and reads your calls in:
  - openings: one of a suit with 12+ points, majors five cards, the longer minor
    otherwise; 1NT 15-17 balanced; 2NT 20-21 balanced; 2C strong and artificial (22+);
    2D/2H/2S weak (6-10, six cards); three of a suit is a preempt;
  - over 1NT: 2C Stayman, 2D/2H/2S to play, 2NT invites, 3 of a major is five cards and
    forcing, 4NT invites 6NT. No transfers;
  - raises: 2 of partner's major 6-9, 3 is 10-12 (limit raise); a new suit by the
    responder is forcing; 1NT response 6-10;
  - after the opponents open: overcalls with a five-card suit, 1NT 15-18, takeout
    doubles; after an overcall a double by responder is negative;
  - 4NT Blackwood (5C none or four, 5D one, 5H two, 5S three) unless it directly raises
    partner's no trumps, when it asks for 6NT.
- **Three difficulties**, the opponents only (partner always plays its best), switchable
  at any time from the buttons on the left:
  - **easy** misjudges its points by a couple, never competes or doubles for penalties,
    and in the play goes for the obvious card, a third of the time just any card;
  - **normal** bids the system and plays by the classic rules: second hand low, third
    hand high, cover an honour with an honour, win as cheaply as possible, draw trumps,
    cash winners, return partner's suit, lead top of a sequence or fourth best;
  - **hard** also opens light and competes by the law of total tricks, and in the play
    deals the unseen cards out many times over (consistent with who has shown out of
    what and what the auction said) and plays each candidate card through to the end,
    keeping the best; with three tricks left it solves them exactly. Nobody ever peeks
    at a hidden hand.
- **Auto** (space) makes the computer call or play for you, at partner's level. It is a
  hint when you are stuck, and it is also how the bots play whole rubbers.
- **Keyboard**: arrows pick a legal card or call, shift (or K) plays it, space is auto.
- **Score** is your side's total on the scoresheet. The shell keeps the high score.
- **New rubber** starts over with the score back at zero.
- The kit's default sound is too loud, so bridge scales it to 0.28 of the setting while
  it is on screen and puts it back when you leave.
- **For playtests**: the `@` sits under your hand, and a `*` marks where your card or
  call goes whenever it is your turn. The smart bot pulses space, which is auto, so it
  plays full rubbers. There is no clock, so an idle player never loses:
  `BRIDGE_IDLE_SECONDS=8` makes doing nothing for that long concede the rubber.
  `BRIDGE_LEVEL=hard` (or `easy`) picks the opponents, and `BRIDGE_TEMPO=0.1` speeds
  the table up so a 60-second run sees several deals.

## Ideas for later

- Show the previous trick on a tap
- Claim the rest of the tricks
- Duplicate or Chicago scoring as options
- Jacoby transfers and other conventions, picked from a list
