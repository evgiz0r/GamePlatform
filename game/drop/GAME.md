# drop

The kit's first 3D game. Built to teach the platform 3D: the shell got `GameMode3D`
(`shell/game_mode_3d.gd`) and this game is the proof it works.

## What is it called?

drop

## Who are you?

The sky. A Tetris piece hovers up there, right where you point.

## What do you do?

Tap somewhere on the plaza and the piece falls there, for real (it tumbles, bounces,
lands). Anyone under it gets squashed. The next piece appears straight away. Arrow keys
aim too, A drops, B (or the on-screen button) rotates the piece a quarter turn.

## What is trying to stop you?

Walkers. They come in from one edge of the plaza and cross to the opposite one, faster
and more of them as time goes on. Every walker that makes it across costs a life. Three
lives.

## How do you win?

Highest score. 10 a squash; landing on two or three at once pays 10 + 20 + 30.

## What should it look like?

A neon plaza at night: glowing kerb, glowing blocks, little glowing people. Blocks that
have landed lie there a couple of seconds, then sink into the ground.

## Core loop

Point, drop, squash, next piece. Miss too many and they walk right past you.
