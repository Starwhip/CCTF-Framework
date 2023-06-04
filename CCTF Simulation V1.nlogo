extensions [csv matrix table]

;;;;;;;;;;;;;;;;;;;;;;;;
;;;    Turtle Data   ;;;
;;;;;;;;;;;;;;;;;;;;;;;;
globals [
  mac-address-list temp-node packet-target destroy-packet next-hop temp target-router
  num-vul-routers num-comp-routers num-off-routers
  environment
  network-center-router router-repair-ticks routing-hold-threshold routing-flush-threshold

  filename

  attacker-awareness
  defender-awareness
  true-awareness

  attackers-won
]

;;Compromise rates in cyberfit model:
;;Base, tactical, industrial
;;Routers: 2% 4% 7%
;;Servers: 3% 13% 7%
;;Users: 15% 7% 3%

;;Using routers in industrial context for current simulation.

breed [routers router] ;;Router agents. Build forwarding tables and route packets
breed [packets packet] ;;Packet agents. Consult router tables to move through the network.

breed [attackers attacker]
breed [attackerScouts attackerScout]

breed [defenders defender]
breed [defenderScouts defenderScout]

directed-link-breed [tcp-links tcp-link] ;;Currently unused
directed-link-breed [ip-links ip-link] ;;Currently unused

directed-link-breed [router-links router-link]
directed-link-breed [packet-links packet-link]
directed-link-breed [def-links def-link]
directed-link-breed [off-links off-link]

routers-own [
  online
  ;;router-mac
  ;;router-ip
  forwarding-table
  vulnerable
  infected
  next-enable-tick
]

packets-own [
  source-router
  destination-router
  packet-data
  time-to-live
]

router-links-own [
  last-update
]
;;;;;;;;;;;;;;;;;;;;;;;;
;;; Setup Procedures ;;;
;;;;;;;;;;;;;;;;;;;;;;;;

to prog-manager
  ;;Batching arguments
  let startDef 1
  let endDef 3
  let startAtt 1
  let endAtt 3

  setup

  ;;Configure defenders from start args
  let def startDef
  let dscout 4 - def

  while [def <= endDef][

    let att startAtt
    let ascout 4 - att

    while [att <= endAtt][

      ;;Ability to repeat with different detection rates.
      let vul 25
      let vulInc 25

      while[vul <= 100]
      [
        let inf 25
        let infInc 25
        while[inf <= 100]
        [

          let vul-chance 0
          while [vul-chance < 7][
            set vul-chance vul-chance + 1

            let take-chance 0
            while [take-chance < 7][
              set take-chance take-chance + 1
              ;;Initialize the simulation parameters
              init def dscout att ascout vul inf vul-chance take-chance

              ;;Repeat a number of iterations.
              repeat 5[

                ;;Setup the program
                reset

                ;;Run for a number of ticks
                while [ticks < 10000][
                  go
                ]

                ;;Close the file
                file-close
              ]
            ]

          ]
          set inf inf + infInc ;;Increment towards 100
        ]

        set vul vul + vulInc ;;Increment towards 100
      ]

      ;;Increment attackers, decrement ascout
      set att att + 1
      set ascout ascout - 1
    ]

    ;;Increment defenders, decrement dscout
    set def def + 1
    set dscout dscout - 1
  ]

end

to init [d ds a as vul-detect inf-detect vul-chance take-chance]
  set numDefenders d
  set numDefenderScouts ds
  set numAttackers a
  set numAttackerScouts as
  set vulnerability-detection-rate vul-detect
  set infection-detection-rate inf-detect
  set router-vulnerability-chance vul-chance
  set router-takeover-chance take-chance
end

to setup
  clear-all
  no-display

  set mac-address-list []
  set attacker-awareness table:make
  set defender-awareness table:make
  set true-awareness table:make

  ;;set-default-shape clients "triangle"
  set-default-shape routers "circle"
  set-default-shape packets "star"
  set-default-shape links "curved"

  set-default-shape def-links "defense"
  set-default-shape off-links "offense"

  set router-repair-ticks 100
  set routing-hold-threshold 5
  set routing-flush-threshold 3

  ifelse empty? import-field[
    generate-network
  ]
  [
    ;matrix-to-network
    ;show "Generated network from matrix"
    list-to-network
  ]

  configure-network-layout

  reset
  display
end

to reset
  file-close
  reset-ticks
  clear-all-plots

  set attackers-won false
  update-troops
  ask routers[
    set forwarding-table []
    set vulnerable 0
    set infected 0
    set online 1
    set next-enable-tick 0
  ]

  ask packets[die]
  ask router-links[
    set last-update 0
  ]
  set attacker-awareness table:make
  set defender-awareness table:make
  set true-awareness table:make

  if(output-file)[
    let SIM-PARAMS (word num-routers "," m0 "," numDefenders "," numDefenderScouts "," numAttackers "," numAttackerScouts "," attacker-move-chance "," vulnerability-spawn-delay "," router-vulnerability-chance "," router-takeover-chance "," vulnerability-detection-rate "," infection-detection-rate)

    set filename open-file export-directory SIM-PARAMS ".csv"

    file-print "#------ Config ------#"

    file-print (word "Number of Routers," "Degree of Network," "Num Defenders," "Num Defender Scouts," "Num Attackers," "Num AttackerScouts," "Attacker Move Chance," "Vul Spawn Delay," "Router Vul Chance," "Router Comp Chance," "Vul Detection Rate," "Comp Detection Rate")

    file-print SIM-PARAMS

    file-print "#------ Prog Start ------#"
    file-print (word "Offline Routers," "Vulnerable Routers," "Compromised Routers," "Defender Situational Awareness")
  ]
end

to-report open-file [directory name ext]
  let basename (word directory name)
  ;; We check to make sure we actually got a string just in case
  ;; the user hits the cancel button.
  if is-string? basename
  [
    ;; If the file already exists, we increment the file version by one, otherwise
    ;; new data would be appended to the old contents.
    let num behaviorspace-run-number
    let file (word basename "-" num ext)
    while [file-exists? file][
      set num num + 1
      set file (word basename "-" num ext)
    ]

    show (word "Opening file " file)
    file-open file

    report file
  ]

  report nobody
end

to go

  if (ticks > blue-team-win-cutoff or attackers-won)[
    file-close
    stop
  ]

  determine-true-awareness
  ;;no-display
  run-router-protocols
  generate-vulnerabilities

  run-troops
  run-packets

  scan-statistics


  ;;display

  ask routers with [online = 0][
    if ticks >= next-enable-tick[
      restart-router self
    ]
  ]

  if output-file[
    write-to-file
  ]

  tick
end


;;;;;;;;;;;;;;;;;;;;;;;
;;; Main Procedures ;;;
;;;;;;;;;;;;;;;;;;;;;;;

to generate-network
  ;; make the initial network of m0 turtles, + one with links
  repeat m0 [let new-router make-router]
  let new-router make-router
  ask new-router[
    ask other routers[
      create-router-link-to new-router
      create-router-link-from new-router
    ]
  ]

  while [count routers < num-routers] [
    ;; new edge is green, old edges are gray
    ask links [ set color gray ]

    ;;Preferrentially attach new routers to the net.
    ba-model-link-node make-router         ;; find partner & use it as attachment
                                           ;; point for new node
    layout
  ]
end

to configure-network-layout
  repeat 5000 [layout]
  resize-nodes

  ;;Determine the central node of the network or pick among equal nodes.

  ;;First sort all routers by number of connections.
  let sorted-routers sort-on [count my-router-links] routers

  ;  foreach sorted-routers [a-router ->
  ;    show a-router
  ;    show count [my-router-links] of a-router
  ;  ]

  ;;Pick the last in the list.
  set network-center-router last sorted-routers
end


to network-to-matrix
  let dimension count routers
  let current-router 0

  let neighbor-matrix matrix:make-constant dimension dimension 0

  repeat dimension[
    let check-router 0

    repeat dimension[
      if not (check-router = current-router)[
        ask router current-router[
          if (router-link-neighbor? router check-router)[
            matrix:set neighbor-matrix check-router current-router 1
          ]
        ]
      ]
      set check-router check-router + 1
    ]
    set current-router current-router + 1
  ]

  let stringmatrix (matrix:pretty-print-text neighbor-matrix)
  ;;print (word "Copy this to import-field \n" stringmatrix)
  set import-field stringmatrix
end

to matrix-to-network
  let network-matrix matrix:from-row-list read-from-string import-field
  set num-routers (item 0 matrix:dimensions network-matrix)

  clear-turtles

  repeat num-routers [let new-router make-router]

  let current-router 0
  repeat num-routers[
    let check-router 0

    repeat num-routers[
      if (matrix:get network-matrix check-router current-router = 1)[
        ask router current-router[
          create-router-link-to router check-router
        ]
      ]
      set check-router check-router + 1
    ]
    set current-router current-router + 1
  ]
end

to network-to-list
  ;;let current-router 0
  let dimension count routers

  let adjacency-list []
  let current-router 0
  repeat dimension[
    ask router current-router[
      let list-entry who
      let adjacent out-router-link-neighbors
      ask adjacent[
        set list-entry (word list-entry " " who)
      ]
      print ""
      set adjacency-list lput (sentence list-entry) adjacency-list
    ]
    set current-router current-router + 1
  ]

  set import-field (word adjacency-list)
end

to list-to-network
  let adjacency-list read-from-string import-field
  set num-routers length adjacency-list

  clear-turtles

  repeat num-routers [let new-router make-router]

  let current-index 0
  repeat num-routers[
    let neighbor-list item current-index adjacency-list
    let current-router item 0 neighbor-list
    let neighbor-item 1
    ask router current-router[
      repeat length neighbor-list - 1[
        create-router-link-to router (item neighbor-item neighbor-list)
        set neighbor-item neighbor-item + 1
      ]
    ]
    set current-index current-index + 1
  ]
end

to generate-network-tree
  clear-turtles
  let sequence []

  repeat num-routers - 2 [
    set sequence lput (random num-routers) sequence
  ]

  generate-tree sequence
  let center [who] of get-tree-center

  clear-turtles
  generate-tree sequence
  layout-radial routers router-links router center

end

to generate-tree [prufer-sequence]
  let remaining []

  let index 0
  repeat num-routers [
    set remaining lput index remaining
    set index index + 1
  ]

  repeat num-routers [let new make-router]

  ;;Get the first/next element of the sequence
  ;;Then get the smallest number that hasn't been added to the tree yet
  ;;Connect these numbers

  set index 0
  while [length remaining > 2] [

    let remaining-index get-smallest-missing-num prufer-sequence remaining
    let num-a item index prufer-sequence
    let num-b item remaining-index remaining

    set remaining remove-item remaining-index remaining

    ask router num-a[
      create-router-link-to router num-b
      create-router-link-from router num-b
    ]


    set prufer-sequence remove-item index prufer-sequence
  ]


  let num-a item index remaining
  let num-b item (index + 1) remaining

  ask router num-a[
    create-router-link-to router num-b
    create-router-link-from router num-b
  ]
end

to-report get-smallest-missing-num [prufer-sequence remaining]

  let index 0
  repeat length remaining[
    let x (item index remaining)
    if not (member? x prufer-sequence)[
      report index
    ]
    set index index + 1
  ]

end

to-report get-tree-center
  let remaining-routers routers

  while [count remaining-routers > 2] [
    ask remaining-routers with [count my-out-links = 1][
      ;; show self
      die
    ]
  ]

  report one-of remaining-routers
end

to generate-vulnerabilities
  if ticks mod vulnerability-spawn-delay = 0[
    ask routers[
      if vulnerable = 0 and online = 1[
        let rand 0
        set rand random 100
        if rand < router-vulnerability-chance[
          set vulnerable 1
          set color yellow
        ]
      ]
    ]
  ]

end

to scan-statistics
  set num-vul-routers 0
  set num-comp-routers 0
  set num-off-routers 0

  ask routers [
    set num-vul-routers (num-vul-routers + vulnerable)
    set num-comp-routers (num-comp-routers + infected)
    set num-off-routers (num-off-routers + 1 - online)
  ] ;;Increment number of vulnerable routers.

end

to router-diagnostics [node]
  ;;Check for detection
  if [vulnerable] of node = 1[
    let detect random 100 ;;0-99
    if detect < vulnerability-detection-rate[
      ;;TODO DETECTION LOGIC
      ;; show "Detected a vulnerable router."

      table:put defender-awareness ([who] of node) "vulnerable"
    ]
  ]

  if [infected] of node = 1[
    let detect random 100 ;;0-99
    if detect < infection-detection-rate[
      ;;TODO DETECTION LOGIC
      ;; show "Detected an infected router."

      table:put defender-awareness ([who] of node) "infected"
    ]
  ]
end

;;Attempt to disinfect a router
to clean-router [node]
  shutdown-router node
  ask node[
    set infected 0
    set vulnerable 0
    set next-enable-tick ticks + restart-time
  ]
end

;;Turn a router off
to shutdown-router [node]
  ask node[
    set forwarding-table []
    set online 0
    set color grey
  ]
end

;;Turn a router back on.
to restart-router [node]
  ask node[
    set online 1
    set color blue
    ifelse infected = 1[
      infect-router node
    ]
    [
      if vulnerable = 1[
        compromise-router node
      ]
    ]
  ]
end

to compromise-router [node]
  ask node[
    set vulnerable 1
    set color yellow
  ]
end

to infect-router [node]
  ask node[
    set infected 1
    set color red
  ]
end

to update-troops
  if (not enable-troops)[
    stop
  ]
  no-display

  ask attackers [die]
  ask attackerScouts [die]
  ask defenders [die]
  ask defenderScouts [die]

  ;;Spawn the offensive and defensive troops.
  if (numDefenderScouts >= numDefenders)[set numDefenderScouts numDefenders - 1]
  if (numAttackerScouts >= numAttackers)[set numAttackerScouts numAttackers - 1]

  let numAttackerWorkers numAttackers - numAttackerScouts
  let numDefenderWorkers numDefenders - numDefenderScouts

  repeat numAttackerWorkers[ make-attacker ]
  repeat numAttackerScouts [make-attackerscout]

  repeat numDefenderWorkers[ make-defender ]
  repeat numDefenderScouts [make-defenderscout]

  layout-circle (turtle-set attackers defenders attackerscouts defenderscouts) (world-width - 50)

  connect-defenders
  connect-attackers

  display
end

;;Make a new defensive troop agent.
to make-defender
  create-defenders 1[
    ;;TODO parameter init
    set color blue
    set shape "square"
    set size 3
  ]
end

;;Make a new defensive troop agent.
to make-defenderscout
  create-defenderscouts 1[
    ;;TODO parameter init
    set color sky
    set shape "square"
    set size 2
  ]
end

;;Used to create a new offensive troop agent
to make-attacker
  create-attackers 1[
    ;;TODO parameter init
    set color red
    set shape "square"
    set size 3
  ]
end

;;Used to create a new offensive troop agent
to make-attackerscout
  create-attackerscouts 1[
    ;;TODO parameter init
    set color orange
    set shape "square"
    set size 2
  ]
end

to connect-defenders
  ask defenders [
    ask my-links [ die ] ;;Remove existing links.
    create-def-link-to network-center-router[ ;one-of routers [ ;;Make a new defense link to a router.
      set color blue
    ]
  ]

  ask defenderscouts [
    ask my-links [ die ] ;;Remove existing links.
    create-def-link-to network-center-router[ ;one-of routers [ ;;Make a new defense link to a router.
      set color sky
    ]
  ]
end

to connect-attackers
  ask attackers [


    connect-attacker self one-of get-periphery-routers ;;Make a new offense link to a router.
  ]

  ask attackerscouts [
    ask my-links [ die ] ;;Remove existing links.

    let periphery routers with [count my-out-router-links = 1]

    create-off-link-to one-of periphery[ ;;Make a new offense link to a router.
      set color orange
    ]
  ]
end

to connect-attacker [agent node]
  ask agent[
    ask my-links [ die ] ;;Remove existing links.
    create-off-link-to node[set color red]
  ]
end

;;Loop to run troops.
to run-troops
  ;;Every packet-rate ticks, send packets.
  if ticks mod packet-spawn-delay = 0 [
    let sources []
    let targets []
    let index 0

    ;;------------------Run scouts ----------------------------

    set sources[]
    set targets[]

    let periphery get-periphery-routers
    ask attackerscouts [
      set sources lput (get-agent-connected-router self) sources
      set targets lput one-of periphery targets ;;Pick routers at random
    ]

    set index 0
    while [index < length sources][
      make-scout-offense-packet item index sources item index targets ;;The router at index of sources -> router at index of targets
      set index index + 1
    ]

    set sources []
    set targets []
    ask defenderscouts [
      set sources lput (get-agent-connected-router self) sources
      set targets lput find-router targets
    ]

    set index 0
    while [index < length sources][
      make-scout-defense-packet item index sources item index targets ;;The router at index of sources -> router at index of targets
      set index index + 1
    ]


    ;;------------------Run attackers ----------------------------
    set sources[]
    set targets[]
    ask attackers [
      if [vulnerable] of get-agent-connected-router self = 0[
        let movechance random 100 ;;A random chance to connect to another router
        if movechance < attacker-move-chance [
          if table:length attacker-awareness > 0 [
            let new get-attacker-new-connection
            if not (new = nobody)[
              connect-attacker self new
            ]
          ]
        ]
      ]

      set sources lput (get-agent-connected-router self) sources
      set targets lput (get-attack-target self) targets
    ]

    set index 0
    while [index < length sources][
      make-offensive-packet item index sources item index targets ;;The router at index of sources -> router at index of targets
      set index index + 1
    ]

    ;;------------------Run defenders ----------------------------
    if (table:length defender-awareness > 0)[
      set sources []
      set targets []
      ask defenders [
        set sources lput (get-agent-connected-router self) sources
        set targets lput (get-defense-target self) targets
      ]

      set index 0
      while [index < length sources][
        make-defensive-packet item index sources item index targets ;;The router at index of sources -> router at index of targets
        set index index + 1
      ]
    ]
  ]

end

to-report get-attacker-new-connection
  let temp-list table:to-list attacker-awareness
  let choices []
  foreach temp-list [ element ->
    if ((item 1 element) = "vulnerable")[
      set choices lput (router item 0 element) choices
    ]
  ]

  let choice nobody
  if (length choices > 0)[
    set choice one-of choices
  ]
  report choice
end

;;When run on an agent, get the router it is connected to
to-report get-agent-connected-router [agent]
  let target nobody
  ask agent[
    if (count my-links <= 0)[stop];
    ask one-of my-links [
      ;;Get the router at the end of the link.
      ask other-end[
        set target self
      ]
    ]
  ]
  report target
end

;;When run on an offensive agent, report the node to send an attack packet to.
to-report get-attack-target [attack-agent]
  let attack-target nobody

  ask attack-agent[
    ;;Get the router linked to this agent.
    ask one-of my-links [
      ;;Get the router at the end of the link.
      ;;Ask the router about the route to the central network node
      ask other-end[
        let nearest-clean-router self

        loop [
          ;;If the retrieved router is infected, find the next one in the path.
          ;;If it is the central router, break out of the loop.
          if nearest-clean-router = nobody [stop]

          if ([infected] of nearest-clean-router = 0)[
            set attack-target nearest-clean-router
            stop
          ]

          set nearest-clean-router route nearest-clean-router network-center-router "attackquery"

          if (nearest-clean-router = network-center-router and [infected] of nearest-clean-router = 1)[
            set attack-target one-of routers
            stop
          ]
        ]
      ]
    ]
  ]

  report attack-target
end

;;When run on a defensive agent, report the node to send a defense packet to.
to-report get-defense-target [defense-agent]
  let temp-list table:to-list defender-awareness
  let infchoices []
  let vulchoices []
  foreach temp-list [ element ->
    if ((item 1 element) = "infected")[
      set infchoices lput (router item 0 element) infchoices
    ]
    if ((item 1 element) = "vulnerable")[
      set vulchoices lput (router item 0 element) vulchoices
    ]
  ]

  let choice nobody
  ifelse (length infchoices > 0)[
    set choice one-of infchoices
  ][
    if (length vulchoices > 0)[
      set choice one-of vulchoices
    ]
  ]
  report choice
end


;; used for creating a new node
to-report make-router
  let new-node nobody
  create-routers 1
  [
    set online 1
    set new-node self
    set infected 0
    set vulnerable 0
    ;;set router-mac make-mac
    ;;set router-ip (word "10.10." count routers ".1")
    set forwarding-table []
  ]

  restart-router new-node
  report new-node
end

;;Used to generate a mac address
to-report make-mac
  let new-address []
  repeat 6 [set new-address lput (word random 16 " " random 16) new-address]

  if length mac-address-list > 0[
    if member? new-address mac-address-list [report make-mac]
    ;;Recursively try again if random new address is in list. Unlikely at our low sample sizes.
  ]
  set mac-address-list lput new-address mac-address-list
  report new-address
end

;;Used to generate an ip address
to-report make-ip [domain]
  ;let new-address []
  ;repeat 4 [set new-address lput random 256 new-address]
  ;;set ip-address-list lput new-address ip-address-list
  let new-address (word random 256 "." random 256 "." random 256 "." random 256)
  report new-address
end

;;Scan and update forwarding tables.
to run-router-protocols
  ;;Update routers every router-broadcast-rate ticks
  if ticks mod router-broadcast-rate = 0[
    ;; show "Routers Broadcasting"
    router-broadcast-neighbors
    ;router-print-tables

    ask routers with [online = 1][
      set forwarding-table remove-duplicates forwarding-table ;;Clean tables after broadcast.

      let flush-table []
      ask my-in-router-links[
        ;;Check for disconnected routers.
        if last-update >= routing-flush-threshold[
          ;; show word "----->flushing router: " other-end
          set flush-table lput other-end flush-table
        ]
      ]

      if length flush-table > 0[
        let new-table []
        foreach forwarding-table[entry ->
          ;;If the destination of the forwarding table entry is a router that has not responded, don't add it to the new list.
          if not (member? item 1 entry flush-table) [
            set new-table lput entry new-table
          ]
        ]
        set forwarding-table new-table
      ]

    ]
  ]
end

to determine-true-awareness
  ask routers[
    let status "clean"
    ifelse(infected = 1)[
      set status "infected"
    ][
      if(vulnerable = 1)[
        set status "vulnerable"
      ]
    ]

    table:put true-awareness ([who] of self) status
  ]
end
to-report calculate-defender-awareness
  ;;Determine actual network state
  let points 0

  let true-list table:to-list true-awareness
  let defender-list table:to-list defender-awareness
  foreach true-list [ element ->
    if(member? element defender-list)[
      set points points + 1
    ]
  ]
  report (points / (count routers))
end




;;Broadcast forwarding tables to nearby routers.
to router-broadcast-neighbors
  ask routers with [online = 1][
    ;;Send the "I am alive" signal to nearby routers
    ask my-out-router-links[
      set last-update 0
    ]

    let direct-routers (link-neighbors with [breed = routers]) ;;These are all routers nearby.

    ;;let my-ip router-ip
    ;;Broadcast a route to myself.
    ask direct-routers[
      let new-entry[]
      set new-entry lput myself new-entry ;;Put broadcasting router's ip in the first position of the table entry (Final destination)
      set new-entry lput myself new-entry ;;Put broadcasting router's ip in the second position of the table entry (Routing target)
      set new-entry lput 1 new-entry ;;This destination is 1 hop away.
      set forwarding-table lput new-entry forwarding-table ;;Add entry to the connected router's forwarding table.
    ]

    ;;Broadcast all known routes to neighbor routers.
    foreach forwarding-table[entry ->
      ask direct-routers[
        ;;Only broadcast if the entry is not a route to myself. Do not advertise routes back to the routers I recieved from.
        if not ((item 0 entry = myself) or (item 1 entry = self))[

          ;;Only add to the table if the route is less than or equal to the hop limit.
          if (item 2 entry + 1) <= hop-limit[

            ;;Add this entry to the table.
            let new-entry []
            set new-entry lput item 0 entry new-entry ;;The destination of the entry
            set new-entry lput myself new-entry;;The ip of the broadcasting router
            set new-entry lput (item 2 entry + 1) new-entry ;;increment hop by 1.
            set forwarding-table lput new-entry forwarding-table
          ]
        ]
      ]
    ]
  ]
end

;;Print a debug statement of all router's forwarding tables.
to router-print-tables
  ask routers[
    foreach forwarding-table[entry ->
      ;; show entry
    ]
  ]
end

to packet-maker [source destination data packet-color]
  create-packets 1[
    set source-router source
    set destination-router destination
    set packet-data data
    set color packet-color
    set time-to-live hop-limit
    set size 3
    create-packet-link-to source
    move-to source
  ]
end

;;Generate a packet for a random client to a random client
to make-packet [data]
  let selection n-of 2 routers
  let router-list []
  ask selection[
    set router-list lput self router-list
  ]
  let source first router-list
  let destination last router-list

  packet-maker source destination data one-of base-colors
end

;;generate an attack packet.
to make-offensive-packet [source destination]
  packet-maker source destination "attack" red
end

;;generate an attack packet.
to make-scout-offense-packet [source destination]
  packet-maker source destination "scoutoffense" orange
end

;;Generate defense packet.
to make-defensive-packet [source destination]
  packet-maker source destination "defend" blue
end

;;generate defense packet.
to make-scout-defense-packet [source destination]
  packet-maker source destination "scoutdefense" sky
end

;;Packet manager.
to run-packets
  ;;Move packets
  if ticks mod packet-update-delay = 0 [
    ask packets[
      set time-to-live time-to-live - 1 ;;Decrement time to live.
      if time-to-live < 1 [timeout-packet self] ;;Kill packet if it is out of time.

      ;;Initialize flag variables
      set packet-target destination-router
      set destroy-packet false

      ;;There is only one link with the packet.
      ask link-neighbors[
        if self = packet-target [
          ;show "Packet has reached destination"
          set destroy-packet true
        ]
      ]

      ifelse destroy-packet[
        ;;Remove this packet, it has reached destination.
        ;;Execute whatever command this packet was designed for.

        if packet-data = "attack" [
          attack-router self
        ]

        if packet-data = "scoutoffense" [
          ifelse ([vulnerable] of packet-target = 1)[
            table:put attacker-awareness [who] of packet-target "vulnerable"
          ][
            table:put attacker-awareness [who] of packet-target "clean"
          ]
        ]

        if packet-data = "defend" [
          defend-router self
        ]

        if packet-data = "scoutdefense" [
          router-diagnostics packet-target
        ]

        die
      ]
      [;; If it isn't at destination, do next hop
        let _data packet-data
        ask link-neighbors[
          set next-hop route self packet-target _data
        ]


        ask my-links[die] ;;Kill links
        if next-hop = nobody[timeout-packet self] ;;
        create-packet-link-to next-hop [set color green] ;;This will either be the location the packet is currently at, or it will be routed to the next destination
      ]
    ]

  ]

  ;;----===== Move Packets =====-----

  ask packets[
    let target nobody
    ask my-links[
      set target other-end
    ]
    face target

    forward distance target / 5
  ]
end


;;Attempt to infect a router.
to attack-router [target-packet]
  ask [destination-router] of target-packet[
    let r random 100 ;;0-99

    ;;If the random roll exceeds the compromise rate of this router, and the router is vulnerable
    if r < router-takeover-chance and vulnerable = 1[
      set infected 1
      set color red

      if(stop-if-attacker-win and self = network-center-router)[
        set attackers-won true
      ]
    ]
  ]
end

;;Attempt to defend a router
to defend-router [target-packet]
  ask [destination-router] of target-packet[
    ;;Make the router not vulnerable and not infected.

    ;;Take the router off of the target lists.
    table:put defender-awareness who "clean"

    if online = 1[
      ifelse infected = 1[
        clean-router self

        ;; update reachable routers
        no-display
        let last-count -1
        let current-count 0
        while [last-count != current-count][
          set last-count current-count
          set current-count 0
          ask routers [if check-router-reachable self[
            set current-count current-count + 1
            ]
          ]
        ]
        display

      ][
        set color blue
        set vulnerable 0
      ]
    ]
  ]
end

;;Time out a packet.
to timeout-packet [packet-to-kill]
  ask packet-to-kill[
    ;; show word self " timed out!"
    die
  ]
end

;;Address resolution protocol approximation; No need to simulate minutia
;;Abstraction of asking links in network to reply with the node with the matching IP address
;;Returns the router with matching IP address, or nobody
to-report router-arp [node target]
  set temp-node node
  ask node[
    ask link-neighbors with [breed = routers][
      ;if reduce and (map = router-ip ip-address)[
      if target = self[
        set temp-node self
      ]
    ]
  ]
  report temp-node
end

to-report route [node destination-node data]
  set target-router nobody

  ask node[
    let min-jump 100000

    ;;If data is not an attack packet, the router is infected and a random number is less than the blackhole-percentage.
    ;    if (not (data = "attack")) and (infected = 1) and random 100 < blackhole-percentage[
    ;      set target-router nobody
    ;      set min-jump -1
    ;    ]

    foreach forwarding-table[entry ->
      if destination-node = item 0 entry[

        let via item 1 entry
        let jump-distance item 2 entry

        if(jump-distance < min-jump)[

          set min-jump jump-distance


          set target-router router-arp self via ;;Get the router agent with the corresponding IP
        ]
      ]
    ]
  ]

  if target-router != nobody [
    if [online] of target-router = 0 [set target-router nobody]
  ]
  report target-router
end

;; This code is the heart of the "preferential attachment" mechanism, and acts like
;; a lottery where each node gets a ticket for every connection it already has.
;; While the basic idea is the same as in the Lottery Example (in the Code Examples
;; section of the Models Library), things are made simpler here by the fact that we
;; can just use the links as if they were the "tickets": we first pick a random link,
;; and than we pick one of the two ends of that link.
to-report find-router
  report [one-of both-ends] of one-of router-links
end

to-report ba-model-pick-nodes
  let m (random m0) + 1 ;;Pick a number of connections "m"

  let picked [] ;;List of picked routers

  loop[
    if length picked >= m [report picked] ;;Report the finished list.

    let new-node find-router ;;Pick a router preferentially.
    if not member? new-node picked [set picked lput new-node picked]  ;;If the picked router is not already picked, add it.
  ]
end

to ba-model-link-node [node]
  let picked ba-model-pick-nodes ;;Find the nodes to connect to.

  foreach picked[agent ->
    ask agent[
      create-router-link-to node
      create-router-link-from node
    ] ;;Link all the picked nodes to the given node.
  ]
end

to-report get-periphery-routers
  report routers with [count my-out-router-links = 1]
end

to-report check-router-reachable [target]
  let start network-center-router
  let found []
  if dfs start target found = false [clean-router target
    report false]
  report true
end

;;Report if a target node is reachable from a start node.
to-report dfs [start target found]
  if [online = 0] of start [report false]
  if start = target [report true]
  ;show target
  let reachable false
  let connected-routers []
  ask start[
    ask my-router-links[
      set connected-routers lput other-end connected-routers
    ]
  ]

  foreach connected-routers[a-router ->

    if not member? a-router found [
      set found lput a-router found

      if [online = 1] of a-router [
        if a-router = target [report true]
      ]

      if dfs a-router target found [report true]
    ]
  ]

  report false
end

to write-to-file
  ;;Output offline routers, vulnerable routers, and compromised routers
  file-print (word num-off-routers "," num-vul-routers "," num-comp-routers "," calculate-defender-awareness)
end
;;;;;;;;;;;;;;
;;; Layout ;;;
;;;;;;;;;;;;;;

;; resize-nodes, change back and forth from size based on degree to a size of 1
to resize-nodes
  ifelse all? routers [size <= 1]
  [
    ;; a node is a circle with diameter determined by
    ;; the SIZE variable; using SQRT makes the circle's
    ;; area proportional to its degree
    ask routers [ set size sqrt count link-neighbors ]
  ]
  [
    ask routers [ set size 1 ]
  ]
end

to layout
  ;; the number 3 here is arbitrary; more repetitions slows down the
  ;; model, but too few gives poor layouts
  repeat 3 [
    ;; the more turtles we have to fit into the same amount of space,
    ;; the smaller the inputs to layout-spring we'll need to use
    let factor sqrt count routers
    ;; numbers here are arbitrarily chosen for pleasing appearance
    layout-spring routers router-links (0.5 / factor) (50 / factor) (10 / factor)
    ;;layout-spring attackers links (0.5 / factor) (50 / factor) (10 / factor)
    ;;layout-spring defenders links (0.5 / factor) (50 / factor) (10 / factor)
    ;display  ;; for smooth animation
  ]
  ;; don't bump the edges of the world
  let x-offset max [xcor] of turtles + min [xcor] of turtles
  let y-offset max [ycor] of turtles + min [ycor] of turtles
  ;; big jumps look funny, so only adjust a little each time
  set x-offset limit-magnitude x-offset 0.1
  set y-offset limit-magnitude y-offset 0.1
  ask routers [ setxy (xcor - x-offset / 2) (ycor - y-offset / 2) ]
end

to-report limit-magnitude [number limit]
  if number > limit [ report limit ]
  if number < (- limit) [ report (- limit) ]
  report number
end


; Copyright 2005 Uri Wilensky.
; See Info tab for full copyright and license.
@#$#@#$#@
GRAPHICS-WINDOW
752
10
1401
660
-1
-1
7.044
1
10
1
1
1
0
0
0
1
-45
45
-45
45
0
0
1
ticks
1000.0

BUTTON
6
25
72
58
NIL
setup
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
93
64
170
97
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

BUTTON
6
64
91
97
go-once
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
7
181
179
214
num-routers
num-routers
10
100
30.0
1
1
Routers
HORIZONTAL

SLIDER
7
222
179
255
m0
m0
1
5
1.0
1
1
degree
HORIZONTAL

SLIDER
8
531
180
564
hop-limit
hop-limit
1
16
16.0
1
1
routers
HORIZONTAL

SLIDER
339
58
511
91
numDefenders
numDefenders
2
10
4.0
1
1
NIL
HORIZONTAL

SLIDER
338
246
510
279
numAttackers
numAttackers
2
10
4.0
1
1
NIL
HORIZONTAL

PLOT
1422
11
1872
319
Router State
ticks
% Routers
0.0
1000.0
0.0
1.0
false
true
"" ""
PENS
"Vulnerable" 1.0 1 -987046 true "" "plot num-vul-routers / count routers"
"Compromised" 1.0 1 -2674135 true "" "plot num-comp-routers / count routers"
"Offline" 1.0 1 -11053225 true "" "plot num-off-routers / count routers"

SLIDER
6
283
218
316
vulnerability-spawn-delay
vulnerability-spawn-delay
1
100
1.0
1
1
ticks
HORIZONTAL

SLIDER
5
453
187
486
packet-spawn-delay
packet-spawn-delay
1
20
1.0
1
1
ticks
HORIZONTAL

BUTTON
7
106
121
139
NIL
file-close
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
8
569
214
602
router-broadcast-rate
router-broadcast-rate
1
100
1.0
1
1
ticks
HORIZONTAL

SLIDER
338
136
585
169
vulnerability-detection-rate
vulnerability-detection-rate
0
100
10.0
1
1
percent
HORIZONTAL

SLIDER
5
412
177
445
restart-time
restart-time
0
1000
10.0
10
1
ticks
HORIZONTAL

BUTTON
336
14
447
47
NIL
update-troops
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
339
96
540
129
numDefenderScouts
numDefenderScouts
1
9
2.0
1
1
NIL
HORIZONTAL

SLIDER
340
283
536
316
numAttackerScouts
numAttackerScouts
1
9
1.0
1
1
NIL
HORIZONTAL

SLIDER
3
490
196
523
packet-update-delay
packet-update-delay
1
20
1.0
1
1
ticks
HORIZONTAL

SLIDER
339
176
566
209
infection-detection-rate
infection-detection-rate
0
100
10.0
1
1
percent
HORIZONTAL

SLIDER
6
319
252
352
router-vulnerability-chance
router-vulnerability-chance
0
100
2.0
1
1
percent
HORIZONTAL

SLIDER
7
356
235
389
router-takeover-chance
router-takeover-chance
0
100
2.0
1
1
percent
HORIZONTAL

SLIDER
343
407
551
440
blue-team-win-cutoff
blue-team-win-cutoff
100
5000
1000.0
100
1
ticks
HORIZONTAL

SLIDER
338
322
558
355
attacker-move-chance
attacker-move-chance
0
100
50.0
1
1
percent
HORIZONTAL

BUTTON
1736
669
1868
702
NIL
network-to-list
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

INPUTBOX
749
673
1574
754
import-field
[[0 23 1] [1 2 0 8 15 5 3] [2 7 4 21 25 6 1 19] [3 1 11] [4 2 20 17] [5 1] [6 2 22] [7 12 9 18 2 13 10] [8 1] [9 14 16 7] [10 7] [11 3 29 24] [12 7] [13 7] [14 9] [15 1] [16 9 26] [17 4] [18 7] [19 27 2] [20 4] [21 2] [22 6] [23 0] [24 11] [25 28 2] [26 16] [27 19] [28 25] [29 11]]
1
0
String

BUTTON
1806
709
1869
742
Clear
set import-field \"\"
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
1422
342
1873
648
Defender Situational Awareness
ticks
% Known
0.0
1000.0
0.0
1.0
false
false
"" ""
PENS
"default" 1.0 1 -13345367 true "" "plot (calculate-defender-awareness)"

SWITCH
341
367
506
400
stop-if-attacker-win
stop-if-attacker-win
1
1
-1000

TEXTBOX
12
158
141
176
Network Setup
11
0.0
1

SWITCH
465
15
598
48
enable-troops
enable-troops
0
1
-1000

SWITCH
512
527
625
560
output-file
output-file
1
1
-1000

INPUTBOX
250
448
630
518
export-directory
NIL
1
0
String

@#$#@#$#@
## WHAT IS IT?

In some networks, a few "hubs" have lots of connections, while everybody else only has a few.  This model shows one way such networks can arise.

Such networks can be found in a surprisingly large range of real world situations, ranging from the connections between websites to the collaborations between actors.

This model generates these networks by a process of "preferential attachment", in which new network members prefer to make a connection to the more popular existing members.

## HOW IT WORKS

The model starts with two nodes connected by an edge.

At each step, a new node is added.  A new node picks an existing node to connect to randomly, but with some bias.  More specifically, a node's chance of being selected is directly proportional to the number of connections it already has, or its "degree." This is the mechanism which is called "preferential attachment."

## HOW TO USE IT

Pressing the GO ONCE button adds one new node.  To continuously add nodes, press GO.

The LAYOUT? switch controls whether or not the layout procedure is run.  This procedure attempts to move the nodes around to make the structure of the network easier to see.

The PLOT? switch turns off the plots which speeds up the model.

The RESIZE-NODES button will make all of the nodes take on a size representative of their degree distribution.  If you press it again the nodes will return to equal size.

If you want the model to run faster, you can turn off the LAYOUT? and PLOT? switches and/or freeze the view (using the on/off button in the control strip over the view). The LAYOUT? switch has the greatest effect on the speed of the model.

If you have LAYOUT? switched off, and then want the network to have a more appealing layout, press the REDO-LAYOUT button which will run the layout-step procedure until you press the button again. You can press REDO-LAYOUT at any time even if you had LAYOUT? switched on and it will try to make the network easier to see.

## THINGS TO NOTICE

The networks that result from running this model are often called "scale-free" or "power law" networks. These are networks in which the distribution of the number of connections of each node is not a normal distribution --- instead it follows what is a called a power law distribution.  Power law distributions are different from normal distributions in that they do not have a peak at the average, and they are more likely to contain extreme values (see Albert & Barabási 2002 for a further description of the frequency and significance of scale-free networks).  Barabási and Albert originally described this mechanism for creating networks, but there are other mechanisms of creating scale-free networks and so the networks created by the mechanism implemented in this model are referred to as Barabási scale-free networks.

You can see the degree distribution of the network in this model by looking at the plots. The top plot is a histogram of the degree of each node.  The bottom plot shows the same data, but both axes are on a logarithmic scale.  When degree distribution follows a power law, it appears as a straight line on the log-log plot.  One simple way to think about power laws is that if there is one node with a degree distribution of 1000, then there will be ten nodes with a degree distribution of 100, and 100 nodes with a degree distribution of 10.

## THINGS TO TRY

Let the model run a little while.  How many nodes are "hubs", that is, have many connections?  How many have only a few?  Does some low degree node ever become a hub?  How often?

Turn off the LAYOUT? switch and freeze the view to speed up the model, then allow a large network to form.  What is the shape of the histogram in the top plot?  What do you see in log-log plot? Notice that the log-log plot is only a straight line for a limited range of values.  Why is this?  Does the degree to which the log-log plot resembles a straight line grow as you add more nodes to the network?

## EXTENDING THE MODEL

Assign an additional attribute to each node.  Make the probability of attachment depend on this new attribute as well as on degree.  (A bias slider could control how much the attribute influences the decision.)

Can the layout algorithm be improved?  Perhaps nodes from different hubs could repel each other more strongly than nodes from the same hub, in order to encourage the hubs to be physically separate in the layout.

## NETWORK CONCEPTS

There are many ways to graphically display networks.  This model uses a common "spring" method where the movement of a node at each time step is the net result of "spring" forces that pulls connected nodes together and repulsion forces that push all the nodes away from each other.  This code is in the `layout-step` procedure. You can force this code to execute any time by pressing the REDO LAYOUT button, and pressing it again when you are happy with the layout.

## NETLOGO FEATURES

Nodes are turtle agents and edges are link agents. The model uses the ONE-OF primitive to chose a random link and the BOTH-ENDS primitive to select the two nodes attached to that link.

The `layout-spring` primitive places the nodes, as if the edges are springs and the nodes are repelling each other.

Though it is not used in this model, there exists a network extension for NetLogo that comes bundled with NetLogo, that has many more network primitives.

## RELATED MODELS

See other models in the Networks section of the Models Library, such as Giant Component.

See also Network Example, in the Code Examples section.

## CREDITS AND REFERENCES

This model is based on:
Albert-László Barabási. Linked: The New Science of Networks, Perseus Publishing, Cambridge, Massachusetts, pages 79-92.

For a more technical treatment, see:
Albert-László Barabási & Reka Albert. Emergence of Scaling in Random Networks, Science, Vol 286, Issue 5439, 15 October 1999, pages 509-512.

The layout algorithm is based on the Fruchterman-Reingold layout algorithm.  More information about this algorithm can be obtained at: http://cs.brown.edu/people/rtamassi/gdhandbook/chapters/force-directed.pdf.

For a model similar to the one described in the first suggested extension, please consult:
W. Brian Arthur, "Urban Systems and Historical Path-Dependence", Chapt. 4 in Urban systems and Infrastructure, J. Ausubel and R. Herman (eds.), National Academy of Sciences, Washington, D.C., 1988.

## HOW TO CITE

If you mention this model or the NetLogo software in a publication, we ask that you include the citations below.

For the model itself:

* Wilensky, U. (2005).  NetLogo Preferential Attachment model.  http://ccl.northwestern.edu/netlogo/models/PreferentialAttachment.  Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.

Please cite the NetLogo software as:

* Wilensky, U. (1999). NetLogo. http://ccl.northwestern.edu/netlogo/. Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.

## COPYRIGHT AND LICENSE

Copyright 2005 Uri Wilensky.

![CC BY-NC-SA 3.0](http://ccl.northwestern.edu/images/creativecommons/byncsa.png)

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 3.0 License.  To view a copy of this license, visit https://creativecommons.org/licenses/by-nc-sa/3.0/ or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

Commercial licenses are also available. To inquire about commercial licenses, please contact Uri Wilensky at uri@northwestern.edu.

<!-- 2005 -->
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.3.0
@#$#@#$#@
set layout? false
set plot? false
setup repeat 300 [ go ]
repeat 100 [ layout ]
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="Multivariable" repetitions="7" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <metric>num-vul-routers</metric>
    <metric>num-comp-routers</metric>
    <metric>num-off-routers</metric>
    <enumeratedValueSet variable="numDefenders">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="numAttackers">
      <value value="5"/>
    </enumeratedValueSet>
    <steppedValueSet variable="numDefenderScouts" first="1" step="1" last="4"/>
    <steppedValueSet variable="numAttackerScouts" first="1" step="1" last="4"/>
    <steppedValueSet variable="vulnerability-detection-rate" first="20" step="20" last="100"/>
    <steppedValueSet variable="infection-detection-rate" first="20" step="20" last="100"/>
    <enumeratedValueSet variable="router-vulnerability-chance">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="router-takeover-chance">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="attacker-move-chance">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="restart-time">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-routers">
      <value value="30"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="import-field">
      <value value="&quot;[[0 7 1 2 9 8] [1 0] [2 5 0 3 13] [3 4 2] [4 25 3] [5 2 24 6] [6 5 10 18 16] [7 0] [8 20 0] [9 22 0] [10 6 15 14 12 11 21] [11 19 10 26] [12 29 28 10 27] [13 2] [14 10] [15 17 10 23] [16 6] [17 15] [18 6] [19 11] [20 8] [21 10] [22 9] [23 15] [24 5] [25 4] [26 11] [27 12] [28 12] [29 12]]&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="router-broadcast-rate">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="packet-update-delay">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="blue-team-win-cutoff">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="vulnerability-spawn-delay">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stop-if-attacker-win">
      <value value="true"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="NetworkCTest" repetitions="5" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <enumeratedValueSet variable="numDefenders">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="numAttackers">
      <value value="10"/>
    </enumeratedValueSet>
    <steppedValueSet variable="numDefenderScouts" first="1" step="1" last="9"/>
    <steppedValueSet variable="numAttackerScouts" first="1" step="1" last="9"/>
    <steppedValueSet variable="vulnerability-detection-rate" first="25" step="25" last="100"/>
    <steppedValueSet variable="infection-detection-rate" first="25" step="25" last="100"/>
    <enumeratedValueSet variable="router-vulnerability-chance">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="router-takeover-chance">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="attacker-move-chance">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="restart-time">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="blue-team-win-cutoff">
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stop-if-attacker-win">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
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

curved
0.5
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

defense
3.0
-0.2 1 1.0 0.0
0.0 1 4.0 4.0
0.2 1 1.0 0.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

offense
-4.0
-0.2 1 4.0 4.0
0.0 1 1.0 0.0
0.2 1 4.0 4.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
