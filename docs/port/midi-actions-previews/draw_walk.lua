-- STAND-IN for docs/port/midi-actions-plan.md: the ASSIGN ALL walkthrough does not exist yet.
screen.clear() screen.aa(0) screen.font_face(1) screen.font_size(8)
screen.level(15) screen.move(0, 8) screen.text("ASSIGN ALL")
screen.rect(70, 1, 58, 9) screen.fill() screen.level(0) screen.move(99, 8) screen.text_center("3 OF 14")
-- progress
screen.level(3) screen.rect(0, 14, 128, 3) screen.stroke()
screen.level(15) screen.rect(0, 14, 128 * 2 / 14, 3) screen.fill()
screen.level(15) screen.font_size(16) screen.move(64, 40) screen.text_center("HOME")
screen.font_size(8) screen.level(6) screen.move(64, 50) screen.text_center("PRESS A PAD OR TURN A KNOB")
screen.level(4) screen.move(0, 60) screen.text("MIX  NOTE 36   TAPE  NOTE 37")
screen.level(15) screen.move(0, 64)
screen.update()
