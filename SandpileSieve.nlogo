globals [
  ;; By always keeping track of how much sand is on the table, we can compute the
  ;; average number of grains per patch instantly, without having to count.
  total
  ;; We don't want the average monitor to updating wildly, so we only have it
  ;; update every tick.
  total-on-tick
  ;; Keep track of avalanche sizes so we can histogram them
  sizes
  ;; Size of the most recent run
  last-size
  ;; Keep track of avalanche lifetimes so we can histogram them
  lifetimes
  ;; Lifetime of the most recent run
  last-lifetime
  ;; The patch the mouse hovers over while exploring
  selected-patch
  ;; These colors define how the patches look normally, after being fired, and in
  ;; explore mode.
  default-color
  fired-color
  selected-color

  alive-patches
  max-comp-patches
  avalanche-patches
]

patches-own [
  ;; how many grains of sand are on this patch
  n
  ;; The total duration of the tasks in a patch
  computed
  ;; The computing capacity in which it consumes n-x-size-grains per cycle (1 default)
  comp-speed
  ;; Whether the patch is considered to be at the borders 1 or not 0
  border
  ;; A list of stored n so that we can easily pop back to a previous state. See
  ;; the NETLOGO FEATURES section of the Info tab for a description of how stacks
  ;; work
  n-stack
  ;; Determines what color to scale when coloring the patch.
  base-color
]

;; The input task says what each patch should do at setup time
;; to compute its initial value for n.  (See the Tasks section
;; of the Programming Guide for information on tasks.)
to setup [setup-task]
  clear-all

  set default-color blue
  set fired-color red
  set selected-color green

  set selected-patch nobody

  set alive-patches patches with [ n > 0]
  set max-comp-patches patches with [ comp-speed = max-comp-speed ]

  ask patches [set border 0]
  if boundary? [
    ask patch  -5 -5 [set border 1]
    ask patch  -5 5 [set border 1]
    ask patch  5 -5 [set border 1]
    ask patch  5 5 [set border 1]
  ]

  ask patches [
    set comp-speed 1
    set n runresult setup-task
    ;set n-x-size-grains runresult setup-task * size-grains
    set computed 0
    set n-stack []
    set base-color default-color
  ]
  let ignore stabilize false
  ask patches [ recolor ]
  set total sum [ n ] of patches
  ;; set this to the empty list so we can add items to it later
  set sizes []
  set lifetimes []
  reset-ticks
end

;; For example, "setup-uniform 2" gives every patch a task which reports 2.
to setup-uniform [initial]
  setup [ -> initial ]
end

;; Every patch uses a task which reports a random value.
to setup-random
  setup [ -> random 4 ]
end

;; patch procedure; the colors are like a stoplight
to recolor
  set pcolor white

  if showing = "grains"
  [
    ;;set pcolor scale-color base-color n 0 4
    set pcolor scale-color blue n 0 4
  ]

  if showing = "comp-power"
  [
    set pcolor scale-color green comp-speed 1 (max-comp-speed + 3)
  ]

  if showing = "borders"
  [
    set pcolor scale-color red (border * 2) 1 3
  ]

  ;if border = 1 [set pcolor scale-color red comp-speed 0 max-comp-speed]
end

to go
  let drop drop-patch
  if drop != nobody [
    ask drop [
      update-n 1 ;size-grains
      recolor
    ]
    let results stabilize animate-avalanches?
    set avalanche-patches first results
    let lifetime last results

    ;; compute the size of the avalanche and throw it on the end of the sizes list
    if any? avalanche-patches [
      set sizes lput (count avalanche-patches) sizes
      set lifetimes lput lifetime lifetimes
    ]
    ;; Display the avalanche and guarantee that the border of the avalanche is updated
    ;; ask avalanche-patches [ recolor ask neighbors4 [ recolor ] ]

    ;; Erase the avalanche
    ask avalanche-patches [ set base-color default-color recolor ]
    ;; Updates the average monitor
    set total-on-tick total
    ;;tick
  ]

  set alive-patches patches with [ n > 0 ]
  set max-comp-patches patches with [ comp-speed = max-comp-speed ]

  ;; Consumption of grains
  if sieve?
  [
    ask patches [
      if n > 0 [
        set computed computed + comp-speed
        if computed >= size-grains [
          set n n - 1
          set computed 0
        ]
      ]

      if n = 0 [
        set comp-speed 1
        set border 0
      ]

      if max-speed? [ if comp-speed > max-comp-speed [set comp-speed max-comp-speed]]

    ]
    if workload?
    [
      if ticks < 50000 [ set size-grains 100 ]
      if ticks > 100000 [ set size-grains 512 ]
      if ticks > 200000 [ set size-grains 1024 ]
      if ticks > 300000 [ set size-grains 2048 ]
      if ticks > 400000 [ set size-grains 3072 ]
      if ticks > 500000 [ stop ]
    ]
  ]
  if boundary? [
    ask patch  -5 -5 [set border 1]
    ask patch  -5 5 [set border 1]
    ask patch  5 -5 [set border 1]
    ask patch  5 5 [set border 1]
  ]
  if not boundary? [ask patches [set border 0]]
  ask patches [recolor]
  display
  tick
end

to explore
  ifelse mouse-inside? [
    let p patch mouse-xcor mouse-ycor
    set selected-patch p
    ask patches [ push-n ]
    ask selected-patch [ update-n 1 ];size-grains ]
    let results stabilize false
    ask patches [ pop-n ]
    ask patches [ set base-color default-color recolor ]
    set avalanche-patches first results
    ask avalanche-patches [ set base-color selected-color recolor ]
    display
  ] [
    if selected-patch != nobody [
      set selected-patch nobody
      ask patches [ set base-color default-color recolor ]
    ]
  ]
end

;; Stabilizes the sandpile. Reports which sites fired and how many iterations it took to
;; stabilize.
to-report stabilize [animate?]
  let active-patches patches with [ n > 4 ]

  ;; The number iterations the avalanche has gone for. Use to calculate lifetimes.
  let iters 0

  ;; we want to count how many patches became overloaded at some point
  ;; during the avalanche, and also flash those patches. so as we go, we'll
  ;; keep adding more patches to to this initially empty set.
  set avalanche-patches no-patches

  while [ any? active-patches ] [
    let overloaded-patches active-patches with [ n > 4 ]
    if any? overloaded-patches [
      set iters iters + 1
    ]
    ask overloaded-patches [
      set base-color fired-color
      ;; subtract 4 from this patch
      ;let size-grain n-x-size-grains / n

      if boundary? [
        if border = 1 [
          set border 0
          ask neighbors4 [
            set border 1
            set comp-speed comp-speed + 1
          ]
        ]
      ]
      update-n -4 ;size-grain
      if animate? [ recolor ]
      ;; edge patches have less than four neighbors, so some sand may fall off the edge
      ask neighbors4 [
        update-n 1 ;size-grain
        if animate? [ recolor ]
      ]
    ]
    if animate? [ display ]
    ;; add the current round of overloaded patches to our record of the avalanche
    ;; the patch-set primitive combines agentsets, removing duplicates
    set avalanche-patches (patch-set avalanche-patches overloaded-patches)
    ;; find the set of patches which *might* be overloaded, so we will check
    ;; them the next time through the loop
    set active-patches patch-set [ neighbors4 ] of overloaded-patches
  ]

  report (list avalanche-patches iters)
end

;; patch procedure. input might be positive or negative, to add or subtract sand
to update-n [ how-much ];size-of-grains ]
  set n n + how-much
  ;set n-x-size-grains n * size-of-grains
  set total total + how-much
end

to-report drop-patch
  if drop-location = "center" [ report patch 0 0 ]
  if drop-location = "random" [ report one-of patches ]
  if drop-location = "mouse-click" and mouse-down? [
    every 0.3 [ report patch mouse-xcor mouse-ycor ]
  ]
  report nobody
end

;; Save the patches state
to push-n ;; patch procedure
  set n-stack fput n n-stack
end

;; restore the patches state
to pop-n ;; patch procedure
  ; need to go through update-n to keep total statistic correct
  update-n ((first n-stack) - n) ;size-grains
  set n-stack but-last n-stack
end


; Public Domain:
; To the extent possible under law, Uri Wilensky has waived all
; copyright and related or neighboring rights to this model.
@#$#@#$#@
GRAPHICS-WINDOW
410
10
843
444
-1
-1
12.9
1
10
1
1
1
0
1
1
1
-16
16
-16
16
1
1
1
ticks
90.0

BUTTON
5
45
150
79
setup uniform
setup-uniform grains-per-patch
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
5
100
150
133
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

PLOT
0
260
310
445
Average grain count
ticks
grains
0.0
1.0
2.0
2.1
true
false
"" ""
PENS
"average" 1.0 0 -16777216 true "" "plot total / count patches"

MONITOR
245
215
310
260
average
total-on-tick / count patches
4
1
11

SWITCH
155
140
325
173
animate-avalanches?
animate-avalanches?
1
1
-1000

CHOOSER
5
140
150
185
drop-location
drop-location
"center" "random" "mouse-click"
1

BUTTON
5
10
150
43
setup random
setup-random
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
200
445
400
595
Avalanche sizes
log size
log count
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "if ticks mod 100 = 0 and not empty? sizes [\n  plot-pen-reset\n  let counts n-values (1 + max sizes) [0]\n  foreach sizes [ the-size ->\n    set counts replace-item the-size counts (1 + item the-size counts)\n  ]\n  let s 0\n  foreach counts [ c ->\n    ; We only care about plotting avalanches (s > 0), but dropping s = 0\n    ; from the counts list is actually more awkward than just ignoring it\n    if (s > 0 and c > 0) [\n      plotxy (log s 10) (log c 10)\n    ]\n    set s s + 1\n  ]\n]"

BUTTON
1045
535
1245
568
clear size and lifetime data
set sizes []\nset lifetimes []\nset-current-plot \"Avalanche lifetimes\"\nset-plot-y-range 0 1\nset-plot-x-range 0 1\nset-current-plot \"Avalanche sizes\"\nset-plot-y-range 0 1\nset-plot-x-range 0 1
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
0
445
200
595
Avalanche lifetimes
log lifetime
log count
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "if ticks mod 100 = 0 and not empty? lifetimes [\n  plot-pen-reset\n  let counts n-values (1 + max lifetimes) [0]\n  foreach lifetimes [ lifetime ->\n    set counts replace-item lifetime counts (1 + item lifetime counts)\n  ]\n  let l 0\n  foreach counts [ c ->\n    ; We only care about plotting avalanches (l > 0), but dropping l = 0\n    ; from the counts list is actually more awkward than just ignoring it\n    if (l > 0 and c > 0) [\n      plotxy (log l 10) (log c 10)\n    ]\n    set l l + 1\n  ]\n]"

BUTTON
5
210
150
243
NIL
explore
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
155
100
325
133
go once
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SLIDER
155
45
325
78
grains-per-patch
grains-per-patch
0
3
0.0
1
1
NIL
HORIZONTAL

SLIDER
675
470
847
503
size-grains
size-grains
0
3072
3072.0
1
1
NIL
HORIZONTAL

SWITCH
530
510
662
543
boundary?
boundary?
0
1
-1000

SWITCH
530
475
633
508
sieve?
sieve?
0
1
-1000

SLIDER
675
545
852
578
max-comp-speed
max-comp-speed
1
100
5.0
1
1
NIL
HORIZONTAL

SWITCH
530
545
672
578
max-speed?
max-speed?
0
1
-1000

PLOT
1165
25
1445
175
average comp power
NIL
NIL
0.0
10.0
1.0
3.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot (sum [comp-speed] of patches) / (count patches)"

PLOT
1165
350
1445
515
active machines
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot count alive-patches"

PLOT
875
180
1160
345
% machines in max power
NIL
NIL
0.0
10.0
0.0
100.0
true
false
"" ""
PENS
"default" 1.0 0 -5298144 true "" "plot (count max-comp-patches) * 100 / count patches"

SWITCH
530
595
657
628
workload?
workload?
1
1
-1000

PLOT
875
25
1160
175
Avalanches
NIL
NIL
0.0
10.0
1.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot count avalanche-patches"

PLOT
875
350
1160
515
workload
NIL
size grains
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot size-grains"

PLOT
1165
180
1445
345
max comp power
NIL
NIL
0.0
10.0
1.0
3.0
true
false
"" ""
PENS
"default" 1.0 0 -5298144 true "" "plot (max [comp-speed] of patches) "

CHOOSER
410
445
525
490
showing
showing
"grains" "comp-power" "borders"
2

@#$#@#$#@
## WHAT IS IT?

The Bak???Tang???Wiesenfeld sandpile model demonstrates the concept of "self-organized criticality". It further demonstrates that complexity can emerge from simple rules and that a system can arrive at a critical state spontaneously rather than through the fine tuning of precise parameters.

## HOW IT WORKS

Imagine a table with sand on it. The surface of the table is a grid of squares. Each square can comfortably hold up to three grains of sand.

Now drop grains of sand on the table, one at a time. When a square reaches the overload threshold of four or more grains, all of the grains (not just the extras) are redistributed to the four neighboring squares.  The neighbors may in turn become overloaded, triggering an "avalanche" of further redistributions.

Sand grains can fall off the edge of the table, helping ensure the avalanche eventually ends.

Real sand grains, of course, don't behave quite like this. You might prefer to imagine that each square is a bureaucrat's desk, with folders of work piling up. When a bureaucrat's desk fills up, she clears her desk by passing the folders to her neighbors.

## HOW TO USE IT

Press one of the **setup** buttons to clear and refill the table. You can start with random sand, or a uniform number of grains per square, using the **setup uniform** button and the **grains-per-patch** slider.

The color scheme in the view is inspired by a "traffic light" pattern:

red = 3 grains
yellow = 2 grains
green = 1 grain
black = 0 grains

If the **display-avalanches?** switch is on, overloaded patches are white.

Press **go** to start dropping sand.  You can choose where to drop with **drop-location**. If the **drop-location** is set to "mouse-click", you can drop sand by clicking on the view (the **go** button needs to be active for that to work.)

If you start out with a uniform distribution of 0 or even 1, it might take a while before you see avalanches. If you want to speed up this process, uncheck "view updates" for a few seconds, and then check it again. This makes the model run faster, because NetLogo does not have to draw the model every tick.

When **display-avalanches?** is on, you can watch each avalanche happening, and then when the avalanche is done, the areas touched by the avalanche flash white.

Push the speed slider to the right to get results faster.

If you press **explore**, hovering over a square with your mouse will show how big the avalanche would be if a grain was dropped on that square.

## THINGS TO NOTICE

The white flashes help you distinguish successive avalanches. They also give you an idea of how big each avalanche was.

Most avalanches are small. Occasionally a much larger one happens. How is it possible that adding one grain of sand at a time can cause so many squares to be affected?

Can you predict when a big avalanche is about to happen? What do you look for?

Leaving **display-avalanches?** on lets you watch the pattern each avalanche makes. How would you describe the patterns you see?

Observe the **Average grain count** plot. What happens to the average height of sand over time?

Observe the **Avalanche sizes** and the **Avalanche lifetimes** plots. This histogram is on a log-log scale, which means both axes are logarithmic. What is the shape of the plots for a long run? You can use the **clear size data** button to throw away size data collected before the system reaches equilibrium.

## THINGS TO TRY

Try all the different combinations of initial setups and drop locations. How does what you see near the beginning of a run differ?  After many ticks have passed, is the behavior still different?

Use an empty initial setup and drop sand grains in the center. This makes the system deterministic. What kind of patterns do you see? Is the sand pile symmetrical and if so, what type of symmetry is it displaying? Why does this happen? Each cell only knows about its neighbors, so how do opposite ends of the pile produce the same pattern if they can't see each other?  What shape is the pile, and why is this? If each cell only adds sand to the cell above, below, left and right of it, shouldn't the resulting pile be cross-shaped too?

Select drop by mouse click. Can you find places where adding one grain will result in an avalanche? If you have a symmetrical pile, then add a few strategic random grains of sand, then continue adding sand to the center of the pile --- what happens to the pattern?

## EXTENDING THE MODEL

Try a larger threshold than 4.

Try including diagonal neighbors in the redistribution, too.

Try redistributing sand to neighbors randomly, rather than always one per neighbor.

This model exhibits characteristics commonly observed in complex natural systems, such as self-organized criticality, fractal geometry, 1/f noise, and power laws.  These concepts are explained in more detail in Per Bak's book (see reference below). Add code to the model to measure these characteristics.

Try coloring each square based on how big the avalanche would be if you dropped another grain on it. To do this, make use of **push-n** and **pop-n** so that you can get back to distribution of grains before calculating the size of the avalanche.

## NETLOGO FEATURES

* In the world settings, wrapping at the world edges is turned off.  Therefore the `neighbors4` primitive sometimes returns only two or three patches.

* In order for the model to run fast, we need to avoid doing any operations that require iterating over all the patches. Avoiding that means keeping track of the set of patches currently involved in an avalanche. The key line of code is:

    `set active-patches patch-set [neighbors4] of overloaded-patches`

* The same `setup` procedure is used to create a uniform initial setup or a random one. The difference is what task we pass it for each pass to run. See the Tasks section of the Programming Guide in the User Manual for more information on Tasks.

* To enable explore mode, this model makes use of a data structure from computer science called a "stack". A stack works just like a stack of papers in real life: you place (or "push") items onto the stack such that the top of the stack is always the item most recently pushed onto it. You may then "pop" items off the top of the stack, revealing their value and removing them from the stack. Hence, stacks are good for saving and restoring the value of a variable. To save a value, you push the variable's value onto the stack, and then set the variable to whatever new value you want. To restore, you pop the value off and set the variable back to that value.

Explore mode actually only ever needs one item on the stack. However, the stack may be used to save as many values as one wants. Hence, you could extend this model to allow people to explore further and further into the future, and then let them pop back to their original place.

## RELATED MODELS

 * Sand
 * Sandpile 3D (in NetLogo 3D)

## CREDITS AND REFERENCES

https://en.wikipedia.org/wiki/Abelian_sandpile_model

https://en.wikipedia.org/wiki/Self-organized_criticality

Bak, P. 1996. How nature works: the science of self-organized criticality. Copernicus, (Springer).

Bak, P., Tang, C., & Wiesenfeld, K. 1987. Self-organized criticality: An explanation of the 1/f noise. Physical Review Letters, 59(4), 381.

The bureaucrats-and-folders metaphor is due to Peter Grassberger.

## HOW TO CITE

If you mention this model or the NetLogo software in a publication, we ask that you include the citations below.

For the model itself:

* Weintrop, D., Tisue, S., Tinker, R., Head, B. and Wilensky, U. (2011).  NetLogo Sandpile model.  http://ccl.northwestern.edu/netlogo/models/Sandpile.  Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.

Please cite the NetLogo software as:

* Wilensky, U. (1999). NetLogo. http://ccl.northwestern.edu/netlogo/. Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.

## COPYRIGHT AND LICENSE

[![CC0](http://ccl.northwestern.edu/images/creativecommons/zero.png)](https://creativecommons.org/publicdomain/zero/1.0/)

Public Domain: To the extent possible under law, Uri Wilensky has waived all copyright and related or neighboring rights to this model.

<!-- 2011 CC0 Cite: Weintrop, D., Tisue, S., Tinker, R., Head, B. -->
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250
@#$#@#$#@
NetLogo 6.0.4
@#$#@#$#@
setup-random repeat 50 [ go ]
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
1
@#$#@#$#@
