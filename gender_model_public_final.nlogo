extensions [nw csv rnd]

breed [women woman]
breed [men man]

turtles-own
[
  current-working-time ;"private activity"
  old-working-time ;"private activity"
  current-transfer-to-woman
  old-transfer-to-woman
  spouse
  conformism
  wage
  number
  preference-private
  current-utility
  memory-change
]

globals
[
  specific-woman
  specific-man
  global-mean-working-time-men
  global-mean-working-time-women
  global-mean-transfer
  current-delta
  history-mean-working-time-men
  history-mean-working-time-women
  average-mean-working-time-women
  average-mean-working-time-men

  women-in-high-public-goods-preference-households
  men-in-high-public-goods-preference-households
  women-in-low-public-goods-preference-households
  men-in-low-public-goods-preference-households
  women-with-above-median-wage-rate
  men-with-above-median-wage-rate
  women-with-below-median-wage-rate
  men-with-below-median-wage-rate
]
to setup
  ca
  set current-delta 0.00001
  set history-mean-working-time-men []
  set history-mean-working-time-women []
  ;makes sure that the networks are reproducible
  if fixed-rs
  [
    random-seed random-seed-fixed
  ]
  ;create and link women with other women, men with other men
  if network-structure = "random-network"
  [
    nw:generate-random men links number-agents-each-type random-network-prob
    nw:generate-random women links number-agents-each-type random-network-prob
  ]
  if network-structure = "watts-strogatz"
  [
    nw:generate-watts-strogatz men links number-agents-each-type watts-strogatz-neighbors watts-strogatz-rewiring
    nw:generate-watts-strogatz women links number-agents-each-type watts-strogatz-neighbors watts-strogatz-rewiring
  ]
  if network-structure = "preferential-attachment"
  [
    nw:generate-preferential-attachment men links number-agents-each-type preferential-attachment-min-degree
    nw:generate-preferential-attachment women links number-agents-each-type preferential-attachment-min-degree
  ]

  if network-structure = "preference-private" or network-structure = "wage" or network-structure = "conformism" or network-structure = "none" or network-structure = "homogenous mixing" or network-structure = "homophily"
  [
    create-women number-agents-each-type
    create-men number-agents-each-type
  ]

  layout-circle men 15
  layout-circle women 15

  ;makes sure that the distribution of preferences, wages etc. is the same across different network specifications
  if fixed-rs
  [
    random-seed random-seed-fixed
  ]


    ;link spouses
    ask women
    [
      set-initials-women
      set spouse one-of men with [spouse = 0]
      ask spouse
      [
        set spouse myself
        set-initials-men
      ]
    ]

  if specific-couple = TRUE
  [
    set specific-woman one-of women
    set specific-man [spouse] of specific-woman
    ask specific-woman
    [
      set wage wage-female-in-question
      set preference-private preference-private-female-in-question
      set conformism conformism-male-in-question
    ]
    ask specific-man
    [
      set wage wage-male-in-question
      set preference-private preference-private-male-in-question
      set conformism conformism-male-in-question
    ]
  ]

  let median-wage-rate-women median [wage] of women
  let median-wage-rate-men median [wage] of men
  let median-preference-private-good-couples median [preference-private + [preference-private] of spouse] of women

  set women-in-high-public-goods-preference-households women with [(preference-private + [preference-private] of spouse) < median-preference-private-good-couples]
  set men-in-high-public-goods-preference-households men with [(preference-private + [preference-private] of spouse) < median-preference-private-good-couples]

  set women-in-low-public-goods-preference-households women with [(preference-private + [preference-private] of spouse) > median-preference-private-good-couples]
  set men-in-low-public-goods-preference-households men with [(preference-private + [preference-private] of spouse) > median-preference-private-good-couples]

  set women-with-above-median-wage-rate women with [wage > median-wage-rate-women]
  set men-with-above-median-wage-rate men with [wage > median-wage-rate-men]

  set women-with-below-median-wage-rate women with [wage < median-wage-rate-women]
  set men-with-below-median-wage-rate men with [wage < median-wage-rate-men]

  if network-structure = "preference-private"  or network-structure = "wage" or network-structure = "conformism"
  [
    generate-network men links preferential-attachment-min-degree network-structure
    generate-network women links preferential-attachment-min-degree network-structure
  ]
  if network-structure = "homophily"
  [
    generate-homophilic-network men links preferential-attachment-min-degree
    generate-homophilic-network women links preferential-attachment-min-degree
  ]
  if import-csv = TRUE
  [
    let i 1
    ask women
    [
      set number i
      ask spouse
      [
        set number i
      ]
      set i i + 1
    ]

    ;transfer from men to women
    file-open "initialTransfer.csv"
    let result csv:from-row file-read-line
    set i 1
    while [ not file-at-end? ] [
      let row csv:from-row file-read-line
      let initial-transfer-imported item 1 row
      ask turtles with [number = i]
      [
        set current-transfer-to-woman initial-transfer-imported
        set old-transfer-to-woman initial-transfer-imported
      ]
      set i i + 1
    ]
    file-close

    ;preference for private good
    file-open "moderatePreferences.csv"
    set result csv:from-row file-read-line
    set i 1
    while [ not file-at-end? ] [
      let row csv:from-row file-read-line
      ask men with [number = i]
      [
        set preference-private item 1 row
      ]
      ask women with [number = i]
      [
        set preference-private item 2 row
      ]
      set i i + 1
    ]
    file-close

    ;preference for private good
    file-open "moderatePreferences.csv"
    set result csv:from-row file-read-line
    set i 1
    while [ not file-at-end? ] [
      let row csv:from-row file-read-line
      ask men with [number = i]
      [
        set preference-private item 1 row
      ]
      ask women with [number = i]
      [
        set preference-private item 2 row
      ]
      set i i + 1
    ]
    file-close

    ;men are at high conformity
    file-open "highConformity.csv"
    set result csv:from-row file-read-line
    set i 1
    while [ not file-at-end? ] [
      let row csv:from-row file-read-line
      ask men with [number = i]
      [
        set conformism item 1 row
      ]

      set i i + 1
    ]
    file-close

    ;women are at moderate conformity
    file-open "moderateConformity.csv"
    set result csv:from-row file-read-line
    set i 1
    while [ not file-at-end? ] [
      let row csv:from-row file-read-line
      ask women with [number = i]
      [
        set conformism item 2 row
      ]

      set i i + 1
    ]
    file-close
  ]
  reset-ticks
  if output-locations = true
  [
    file-close-all
    let file-name (word "agent_position_" behaviorspace-experiment-name "_" behaviorspace-run-number ".csv")
    if file-exists? file-name
    [
      file-delete file-name
    ]
    file-open file-name
    file-print "agentid,agenttype,period,workingtime,transfer,networkstructure"
    print-agent-positions
  ]
end

to set-initials-women
  set shape "female"
  set xcor xcor - 20
  set current-working-time norm-paid-time-female / 100
  set old-working-time norm-paid-time-female / 100
  set current-transfer-to-woman min(list 1 max(list 0 random-normal initial-transfer (initial-transfer * std-dev-values)))
  set old-transfer-to-woman current-transfer-to-woman
  set wage max(list 0 random-normal wage-female ((wage-male + wage-female) / 2 * std-dev-values))
  set conformism max(list 0 random-normal conformism-female ( std-dev-values * (conformism-male + conformism-female) / 2))
  set preference-private min(list 0.99 max(list 0.01 random-normal preference-private-mean-female (std-dev-values * (preference-private-mean-male + preference-private-mean-female) / 2)))
  set size 2
  set memory-change []
end

to set-initials-men
  set shape "male"
  set xcor xcor + 20
  set old-working-time norm-paid-time-male / 100
  set current-working-time norm-paid-time-male / 100
  set current-transfer-to-woman [current-transfer-to-woman] of spouse
  set old-transfer-to-woman current-transfer-to-woman
  set wage max(list 0 random-normal wage-male ((wage-male + wage-female) / 2 * std-dev-values))
  set conformism max(list 0 random-normal conformism-male ( std-dev-values * (conformism-male + conformism-female) / 2))
  set preference-private min(list 0.99 max(list 0.01 random-normal preference-private-mean-male (std-dev-values * (preference-private-mean-male + preference-private-mean-female) / 2)))
  ;set preference-private [preference-private] of spouse
  ;set preference-private min(list 1 max(list 0 random-normal preference-private-mean std-dev-values))
  set size 2
  set memory-change []
end

to generate-network [agent-breed link-breed number-min-degrees variable-in-question]
  run (word "ask " agent-breed " [ create-" link-breed "-with rnd:weighted-n-of " number-min-degrees " other " agent-breed " [1 / abs ([" variable-in-question "] of myself - " variable-in-question " - random-normal 0 0.001)]]" )
end

to generate-homophilic-network [agent-breed link-breed number-min-degrees]
  run (word "ask " agent-breed " [ create-" link-breed "-with rnd:weighted-n-of " number-min-degrees " other " agent-breed " [1 / (abs ([conformism] of myself - conformism - random-normal 0 0.001) + abs ([wage] of myself - wage) + abs ([preference-private] of myself - preference-private))]]" )
end

to go
  set-theta
  update-statistics
  tick
  if output-locations = true
  [
    print-agent-positions
  ]
end

to set-theta
  ask women
  [
    let chosen-bundle choose-bundle self spouse 0
    let utility_outside_option_woman calculate-utility self ((item 0 chosen-bundle))  0
    let utility_outside_option_man calculate-utility spouse ((item 1 chosen-bundle))  0
    let delta-theta 0.001
    let tested-theta current-transfer-to-woman
    let best-theta 0
    let best-payoff 0;calculate-payoff self spouse 0 utility_outside_option_woman utility_outside_option_man
    let change 1
    while [tested-theta <= 1 and change > 0]
    [
      set tested-theta tested-theta + delta-theta
      let calculated-payoff calculate-payoff self spouse tested-theta utility_outside_option_woman utility_outside_option_man
      ifelse calculated-payoff > best-payoff
      [
        set best-payoff calculated-payoff
        set best-theta tested-theta
      ]
      [
        set change 0
      ]

    ]
    set change 1
    set tested-theta current-transfer-to-woman
    while [tested-theta >= -1 and change > 0]
    [
      set tested-theta tested-theta - delta-theta
      let calculated-payoff calculate-payoff self spouse tested-theta utility_outside_option_woman utility_outside_option_man
      ifelse calculated-payoff > best-payoff
      [
        set best-payoff calculated-payoff
        set best-theta tested-theta
      ]
      [
        set change 0
      ]
        ;show (word tested-theta " " calculated-payoff "  " best-theta "  " best-payoff)

    ]
    set chosen-bundle choose-bundle self spouse best-theta
    set current-transfer-to-woman best-theta
    set current-working-time  item 0 chosen-bundle
    ask spouse
    [
      set current-transfer-to-woman  best-theta
      set current-working-time  item 1 chosen-bundle
    ]

  ]
  ;transfer-to-woman
end

to set-theta-index [index]
  ;let index 100
  ;while [index <= 199]
  ;[
    ask woman index
    [

      let chosen-bundle choose-bundle self spouse 0
    ;show (word chosen-bundle)
      ;let utility_outside_option_woman calculate-utility self (precision (item 0 chosen-bundle) 3)  0
      ;let utility_outside_option_man calculate-utility spouse (precision (item 1 chosen-bundle) 3)  0
      let utility_outside_option_woman calculate-utility self ((item 0 chosen-bundle))  0
    ;show (word utility_outside_option_woman)
      let utility_outside_option_man calculate-utility spouse ((item 1 chosen-bundle))  0
    ;show (word utility_outside_option_man)
      let tested-theta -1
      let best-theta 0
      let best-payoff calculate-payoff self spouse 0 utility_outside_option_woman utility_outside_option_man
      while [tested-theta <= 1]
      [
        ;show (word "tested theta   " tested-theta "utility outside option woman: " utility_outside_option_woman "utility outside option man: " utility_outside_option_man)

        let calculated-payoff calculate-payoff self spouse tested-theta utility_outside_option_woman utility_outside_option_man
        if calculated-payoff > best-payoff
        [
          set best-payoff calculated-payoff
          set best-theta tested-theta
        ]
        ;show (word tested-theta " calculated payoff: " calculated-payoff " best-theta: " best-theta " best-payoff: " best-payoff)
        set tested-theta precision (tested-theta + 0.001) 3
      ]
      set chosen-bundle choose-bundle self spouse best-theta
      ;set current-transfer-to-woman (precision best-theta 3)
      ;set current-working-time (precision item 0 chosen-bundle 2 )
      set current-transfer-to-woman best-theta
      set current-working-time  item 0 chosen-bundle
      ask spouse
      [
        ;set current-transfer-to-woman (precision best-theta 3)
        ;set current-working-time (precision item 1 chosen-bundle 2 )
        set current-transfer-to-woman  best-theta
        set current-working-time  item 1 chosen-bundle
      ]
      ;show (word "woman " index " completed")
    ]
    set index index + 1
  ;]
  ;transfer-to-woman
end

to-report calculate-payoff [relevant-woman relevant-man transfer-to-woman utility-outside-option-woman utility-outside-option-man]
  let chosen-bundle choose-bundle relevant-woman relevant-man transfer-to-woman
  ;let payoff-man (precision (calculate-utility relevant-man (item 1 chosen-bundle) transfer-to-woman) 3 ) - utility-outside-option-man
  ;let payoff-woman (precision (calculate-utility relevant-woman (item 0 chosen-bundle) transfer-to-woman) 3) - utility-outside-option-woman
  let payoff-man  precision (calculate-utility relevant-man (item 1 chosen-bundle) transfer-to-woman ) 8 - precision utility-outside-option-man 8
  let payoff-woman precision (calculate-utility relevant-woman (item 0 chosen-bundle) transfer-to-woman) 8 - precision utility-outside-option-woman 8
  ifelse payoff-man >= 0 and payoff-woman >= 0
  [
    report payoff-man * payoff-woman
  ]
  [
    report -1
  ]
end

to-report choose-bundle [relevant-woman relevant-man transfer-to-woman]

  let change-a 1
  let change-b 1
  ask relevant-woman
  [
    set memory-change []
  ]
  ask relevant-man
  [
    set memory-change []
  ]
  while [(change-a + change-b) > 0]
  [

    ask (turtle-set relevant-woman relevant-man)
    [
      let currently-optimized-working-time current-working-time
      set current-utility calculate-utility self current-working-time transfer-to-woman
      let delta (- current-delta);-0.0001
      ;important if agents are "stuck" to choose between two adjacent values
      let sum-memory-change  1
      if length memory-change > 0
      [
        set sum-memory-change (abs sum [memory-change] of relevant-woman) + (abs sum [memory-change] of relevant-man)
      ]
      while [delta <= current-delta]
      [
        let change-d 1
        while [change-d > 0 and (delta + current-working-time) >= 0 and (delta + current-working-time) <= 1 and sum-memory-change != 0]
        [
          let candidate-payoff calculate-utility self (current-working-time + delta) transfer-to-woman
          set change-d candidate-payoff - current-utility
          ;show (word "tested working time: " (delta + current-working-time) ", calculated payoff: " candidate-payoff ", reference working time: " current-working-time  ", reference payoff: " currently-best-payoff)
          if change-d > 0
          [
            set current-working-time max( list 0 min (list 1 (current-working-time + delta)))
            set current-utility candidate-payoff
            set memory-change fput delta memory-change
            if length memory-change > 10
            [
              set memory-change but-last memory-change
            ]

            ;set currently-best-payoff candidate-payoff
          ]
        ]
        ;set current-working-time calculate-optimal-working-time [current-working-time] of spouse transfer-to-woman
        set delta delta + (current-delta * 2);0.0002
      ]
      ifelse is-woman? self
      [
        set change-a abs (current-working-time - currently-optimized-working-time )
      ]
      [
        set change-b abs (current-working-time - currently-optimized-working-time )
      ]
    ]
;    ask relevant-man
;    [
;      let currently-optimized-working-time current-working-time
;      let currently-best-payoff calculate-utility self current-working-time transfer-to-woman
;      let delta -0.01
;      while  [delta <= 0.01]
;      [
;        let change-d 1
;        while [change-d >= 0.01 and (delta + current-working-time) >= 0 and (delta + current-working-time) <= 1]
;        [
;          let candidate-payoff calculate-utility self (current-working-time + delta) transfer-to-woman
;          set change-d candidate-payoff - currently-best-payoff
;          if change-d > 0
;          [
;            set current-working-time max( list 0 min (list 1 (current-working-time + delta)))
;            set currently-best-payoff candidate-payoff
;          ]
;
;        ]
;        ;set current-working-time calculate-optimal-working-time [current-working-time] of spouse transfer-to-woman
;        set delta delta + 0.02
;      ]
;      set change-b abs (current-working-time - currently-optimized-working-time )
;    ]
  ]
  report (list [current-working-time] of relevant-woman [current-working-time] of relevant-man)
end

;to-report calculate-optimal-working-time [working-time-spouse transfer-to-woman]
;
;  let relevant-transfer transfer-to-woman ;positive: agent gives money
;  let recipient false
;  if transfer-to-woman < 0
;  [
;    set recipient true
;  ]
;  let perception-norm-division-of-labor mean [old-working-time] of link-neighbors
;  let perception-norm-transfer-to-women mean [old-transfer-to-woman] of link-neighbors
;  if is-woman? self
;  [
;    if transfer-to-woman > 0
;    [
;      set recipient true
;    ]
;    set relevant-transfer (- transfer-to-woman)
;  ]
;  let working-time-self current-working-time
;  ;return working-time male, working time female, transfer-to-woman
;
;  ifelse recipient = true
;  [
;
;    report  sqrt (preference-private * (working-time-self * wage ) + (1 - preference-private) * sqrt ( 2 - working-time-self - working-time-spouse)) * exp( - conformism  * (working-time-self - perception-norm-division-of-labor) ^ 2 - conformism  * (transfer-to-woman - perception-norm-transfer-to-women) ^ 2 )
;  ]
;  [
;  ]
;
;end



to-report calculate-utility [agent working-time-self transfer-to-woman]

  ;let relevant-transfer precision transfer-to-woman 3  ;positive: agent gives money
  let relevant-transfer transfer-to-woman
  if is-woman? agent
  [
    set relevant-transfer (- transfer-to-woman)
  ]

  let recipient false
  if relevant-transfer < 0
  [
    set recipient true
  ]
  let perception-norm-division-of-labor [old-working-time] of agent
  let perception-norm-transfer-to-women [old-transfer-to-woman] of agent
  let perception-norm-division-of-labor-spouse [old-working-time] of spouse

  ifelse any? [link-neighbors] of agent
  [
    set perception-norm-division-of-labor mean [old-working-time] of [link-neighbors] of agent
    set perception-norm-division-of-labor-spouse mean [[old-working-time] of (turtle-set [spouse] of link-neighbors)] of agent
    set perception-norm-transfer-to-women mean [old-transfer-to-woman] of [link-neighbors] of agent
  ]
  [
    if network-structure = "homogenous mixing"
    [
      ifelse is-woman? agent
      [
        set perception-norm-division-of-labor global-mean-working-time-women
        set perception-norm-division-of-labor-spouse global-mean-working-time-men
      ]
      [
        set perception-norm-division-of-labor global-mean-working-time-men
        set perception-norm-division-of-labor-spouse global-mean-working-time-women
      ]
      set perception-norm-transfer-to-women global-mean-transfer

    ]
  ]

  let working-time-spouse [current-working-time] of [spouse] of agent
  let wage-spouse [wage]  of [spouse] of agent
  let relevant-conformism [conformism] of agent
  let norm-parameter ( - relevant-conformism  * ( weight-working-time-self * (working-time-self - perception-norm-division-of-labor) ^ 2 + weight-transfer * (transfer-to-woman - perception-norm-transfer-to-women) ^ 2 + weight-working-time-partner * (working-time-spouse - perception-norm-division-of-labor-spouse) ^ 2))
  ;let norm-parameter ( - relevant-conformism  * (working-time-self - perception-norm-division-of-labor) ^ 2 - relevant-conformism  * (transfer-to-woman - perception-norm-transfer-to-women) ^ 2)
  ;if norm-with-partner
  ;[
  ;  set norm-parameter norm-parameter - relevant-conformism  * (working-time-spouse - perception-norm-division-of-labor-spouse) ^ 2
  ;]
  ;return working-time male, working time female, transfer-to-woman
  ifelse recipient = true
  [
    ifelse (working-time-self * [wage] of agent + (abs relevant-transfer) * wage-spouse * working-time-spouse) > 0 and (working-time-self <= 1) and (working-time-spouse <= 1)
    [
      if utility-function = "additive"
      [
        ;report ( preference-private * sqrt ( (working-time-self * [wage] of agent + (abs relevant-transfer) * wage-spouse * working-time-spouse )) + (1 - preference-private) * sqrt ( ( 2 - working-time-self - working-time-spouse))) * exp( - relevant-conformism  * (working-time-self - perception-norm-division-of-labor) ^ 2 - relevant-conformism  * (transfer-to-woman - perception-norm-transfer-to-women) ^ 2 )
        report ( [preference-private] of agent * sqrt ( (working-time-self * [wage] of agent + (abs relevant-transfer) * wage-spouse * working-time-spouse )) + (1 - [preference-private] of agent) * sqrt ( ( 2 - working-time-self - working-time-spouse)))  * exp (norm-parameter)
        ;report ( preference-private * sqrt ( (working-time-self * [wage] of agent + (abs relevant-transfer) * wage-spouse * working-time-spouse )) + (1 - preference-private) * sqrt ( ( 2 - working-time-self - working-time-spouse))) ^ 2 * exp( -  relevant-conformism  * (transfer-to-woman - perception-norm-transfer-to-women) ^ 2 )
      ]
      if utility-function = "CES"
      [
        ;report ( preference-private * sqrt ( (working-time-self * [wage] of agent + (abs relevant-transfer) * wage-spouse * working-time-spouse )) + (1 - preference-private) * sqrt ( ( 2 - working-time-self - working-time-spouse))) * exp( - relevant-conformism  * (working-time-self - perception-norm-division-of-labor) ^ 2 - relevant-conformism  * (transfer-to-woman - perception-norm-transfer-to-women) ^ 2 )
        report (( [preference-private] of agent * ( ( (working-time-self * [wage] of agent + (abs relevant-transfer) * wage-spouse * working-time-spouse )) ^ CES_beta) + (1 - [preference-private] of agent) * ( ( ( 2 - working-time-self - working-time-spouse)) ^ CES_beta)) ^ ( 1 / CES_beta))  * exp (norm-parameter)
        ;report ( preference-private * sqrt ( (working-time-self * [wage] of agent + (abs relevant-transfer) * wage-spouse * working-time-spouse )) + (1 - preference-private) * sqrt ( ( 2 - working-time-self - working-time-spouse))) ^ 2 * exp( -  relevant-conformism  * (transfer-to-woman - perception-norm-transfer-to-women) ^ 2 )
      ]
      if utility-function = "multiplicative"
      [
        report ( sqrt (working-time-self * [wage] of agent + (abs relevant-transfer) * wage-spouse * working-time-spouse ) * sqrt ( 2 - working-time-self - working-time-spouse))  * exp (norm-parameter)
      ]
      if utility-function = "multiplicative including weights"
      [
        report ( ((working-time-self * [wage] of agent + (abs relevant-transfer) * wage-spouse * working-time-spouse ) ^ [preference-private] of agent) * (( 2 - working-time-self - working-time-spouse) ^ (1 - [preference-private] of agent)))   * exp (norm-parameter)
      ]
    ]
    [
      report -200
    ]
  ]
  [
    ifelse working-time-self * [wage] of agent * (1 - relevant-transfer) > 0  and (working-time-self <= 1) and (working-time-spouse <= 1)
    [
      if utility-function = "additive" ;actually CES
      [
        ;report ( preference-private * sqrt ( working-time-self * [wage] of agent * (1 - relevant-transfer) ) + (1 - preference-private) * sqrt ( ( 2 - working-time-self - working-time-spouse))) * exp( - relevant-conformism  * (working-time-self - perception-norm-division-of-labor) ^ 2 - relevant-conformism  * (transfer-to-woman - perception-norm-transfer-to-women) ^ 2 )
        report ( [preference-private] of agent * sqrt ( working-time-self * [wage] of agent * (1 - relevant-transfer) ) + (1 - [preference-private] of agent) * sqrt ( ( 2 - working-time-self - working-time-spouse)))  * exp (norm-parameter)
        ;report ( preference-private * sqrt ( working-time-self * [wage] of agent * (1 - relevant-transfer) ) + (1 - preference-private) * sqrt ( ( 2 - working-time-self - working-time-spouse))) ^ 2 * exp( - relevant-conformism  * (transfer-to-woman - perception-norm-transfer-to-women) ^ 2 )
      ]
      if utility-function = "CES" ;actually CES
      [
        ;report ( preference-private * sqrt ( working-time-self * [wage] of agent * (1 - relevant-transfer) ) + (1 - preference-private) * sqrt ( ( 2 - working-time-self - working-time-spouse))) * exp( - relevant-conformism  * (working-time-self - perception-norm-division-of-labor) ^ 2 - relevant-conformism  * (transfer-to-woman - perception-norm-transfer-to-women) ^ 2 )
        report (( [preference-private] of agent * ( ( working-time-self * [wage] of agent * (1 - relevant-transfer) ) ^ CES_beta) + (1 - [preference-private] of agent) * ( ( ( 2 - working-time-self - working-time-spouse)) ^ CES_beta)) ^ (1 / CES_beta))  * exp (norm-parameter)
        ;report ( preference-private * sqrt ( working-time-self * [wage] of agent * (1 - relevant-transfer) ) + (1 - preference-private) * sqrt ( ( 2 - working-time-self - working-time-spouse))) ^ 2 * exp( - relevant-conformism  * (transfer-to-woman - perception-norm-transfer-to-women) ^ 2 )      ]
      ]
        if utility-function = "multiplicative"
      [
        report ( sqrt (working-time-self * [wage] of agent * (1 - relevant-transfer)) * sqrt ( 2 - working-time-self - working-time-spouse))  * exp (norm-parameter)
      ]

      if utility-function = "multiplicative including weights"
      [
        report ( (working-time-self * [wage] of agent * (1 - relevant-transfer)) ^ [preference-private] of agent * ( 2 - working-time-self - working-time-spouse))  ^ ( 1 - [preference-private] of agent)  * exp (norm-parameter)
      ]
    ]
    [
      report -200
    ]
  ]
end

to update-statistics
  ask turtles
  [
    set old-working-time current-working-time ;"private activity"
    set old-transfer-to-woman current-transfer-to-woman ;"private activity"
  ]
  set global-mean-working-time-men mean [current-working-time] of men
  set global-mean-working-time-women mean [current-working-time] of women

  ;if values oscillate around an equilibrium, increase precision
;  if length history-mean-working-time-women > 9
;  [
;    if ((global-mean-working-time-women != item 0 history-mean-working-time-women and member? global-mean-working-time-women but-first history-mean-working-time-women) or (global-mean-working-time-men != item 0 history-mean-working-time-men and member? global-mean-working-time-men but-first history-mean-working-time-men))
;    [
;      set current-delta current-delta / 2
;      set history-mean-working-time-women []
;      set history-mean-working-time-men []
;    ]
;  ]
  set history-mean-working-time-men fput global-mean-working-time-men history-mean-working-time-men
    if length history-mean-working-time-men > 10
  [
    set history-mean-working-time-men but-last history-mean-working-time-men
  ]
  set history-mean-working-time-women fput global-mean-working-time-women history-mean-working-time-women
  if length history-mean-working-time-women > 10
  [
    set history-mean-working-time-women but-last history-mean-working-time-women
  ]
  set average-mean-working-time-women mean history-mean-working-time-women
  set average-mean-working-time-men mean history-mean-working-time-men
  set global-mean-transfer mean [current-transfer-to-woman] of women
end

to-report calc-pct [ #pct #vals ]
  let #listvals sort #vals
  let #pct-position #pct / 100 * length #vals
  ; find the ranks and values on either side of the desired percentile
  let #low-rank floor #pct-position
  let #low-val item #low-rank #listvals
  let #high-rank ceiling #pct-position
  let #high-val item #high-rank #listvals
  ; interpolate
  ifelse #high-rank = #low-rank
  [ report #low-val ]
  [ report #low-val + ((#pct-position - #low-rank) / (#high-rank - #low-rank)) * (#high-val - #low-val) ]
end

to print-agent-positions
  ask turtles
  [
    file-print (word who "," breed "," ticks "," current-working-time "," current-transfer-to-woman "," network-structure)
  ]
end


;to-report calculate-best-working-time [working-time-spouse transfer-to-woman]
;
;  let relevant-transfer transfer-to-women ;positive: agent gives money
;  let perception-norm-division-of-labor mean [current-working-time] of link-neighbors
;  let perception-norm-transfer-to-women mean [current-transfer-to-woman] of link-neighbors
;  if is-woman? self
;  [
;    set relevant-transfer (- transfer-to-women)
;  ]
;  let working_time-self current-working-time
;  ;return working-time male, working time female, transfer-to-woman
;    report (list  sqrt (preference-private * (working-time-self * wage ) + (1 - preference-private) * sqrt ( 2 - working-time-self - working-time-spouse)) * exp( - conformism  * (working-time-self - perception-norm-division-of-labor) ^ 2 - conformism  * (transfer-to-women - perception-norm-transfer-to-women) ^ 2 ))
;
;
;end
@#$#@#$#@
GRAPHICS-WINDOW
238
12
1247
450
-1
-1
13.0
1
10
1
1
1
0
0
0
1
-38
38
-16
16
0
0
1
ticks
30.0

INPUTBOX
5
151
200
211
wage-female
0.75
1
0
Number

INPUTBOX
5
216
200
276
wage-male
1.0
1
0
Number

SLIDER
4
282
200
315
norm-paid-time-male
norm-paid-time-male
0
100
80.0
1
1
%
HORIZONTAL

SLIDER
4
325
201
358
norm-paid-time-female
norm-paid-time-female
0
100
20.0
1
1
%
HORIZONTAL

CHOOSER
6
433
200
478
network-structure
network-structure
"random-network" "watts-strogatz" "preferential-attachment" "preference-private" "wage" "conformism" "none" "homogenous mixing" "homophily"
6

SLIDER
8
483
198
516
random-network-prob
random-network-prob
0
1
0.01
0.01
1
NIL
HORIZONTAL

INPUTBOX
8
522
202
582
watts-strogatz-neighbors
2.0
1
0
Number

SLIDER
10
591
200
624
watts-strogatz-rewiring
watts-strogatz-rewiring
0
1
0.1
0.01
1
NIL
HORIZONTAL

INPUTBOX
5
363
202
423
number-agents-each-type
20.0
1
0
Number

INPUTBOX
12
630
206
690
preferential-attachment-min-degree
2.0
1
0
Number

BUTTON
4
10
70
43
setup
if fixed-rs\n[\nrandom-seed random-seed-fixed\n]\nsetup
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
149
11
220
44
hide links
ask links [hide-link]
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
83
10
139
43
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
1

SLIDER
0
705
224
738
preference-private-mean-male
preference-private-mean-male
0
1
0.5
0.01
1
NIL
HORIZONTAL

PLOT
781
475
1349
722
plot 1
NIL
NIL
0.0
1.0
0.0
1.0
true
true
"" ""
PENS
"working time women" 1.0 0 -2674135 true "" "plot mean [current-working-time] of women"
"working time men" 1.0 0 -13345367 true "" "plot mean [current-working-time] of men"
"transfer to women" 1.0 0 -16449023 true "" "plot mean [current-transfer-to-woman] of men"
"average working time women" 1.0 0 -955883 true "" "plot average-mean-working-time-women"

SLIDER
237
705
410
738
initial-transfer
initial-transfer
0
1
0.1
0.01
1
NIL
HORIZONTAL

INPUTBOX
224
640
380
700
conformism-male
3.0
1
0
Number

INPUTBOX
222
579
378
639
conformism-female
0.0
1
0
Number

CHOOSER
213
469
429
514
utility-function
utility-function
"additive" "CES" "multiplicative" "multiplicative including weights"
1

SWITCH
6
53
122
86
import-csv
import-csv
1
1
-1000

INPUTBOX
221
521
376
581
std-dev-values
0.2
1
0
Number

SWITCH
123
53
234
86
fixed-rs
fixed-rs
0
1
-1000

INPUTBOX
7
88
109
148
random-seed-fixed
1.0
1
0
Number

SLIDER
0
745
231
778
preference-private-mean-female
preference-private-mean-female
0
1
0.5
0.01
1
NIL
HORIZONTAL

INPUTBOX
442
526
597
586
wage-female-in-question
2.0
1
0
Number

INPUTBOX
441
592
596
652
wage-male-in-question
2.0
1
0
Number

INPUTBOX
442
661
597
721
preference-private-female-in-question
0.5
1
0
Number

INPUTBOX
442
724
597
784
preference-private-male-in-question
0.5
1
0
Number

SWITCH
445
457
581
490
specific-couple
specific-couple
1
1
-1000

INPUTBOX
603
526
768
586
conformism-male-in-question
1.0
1
0
Number

INPUTBOX
603
595
768
655
conformism-female-in-question
1.0
1
0
Number

INPUTBOX
595
463
750
523
CES_beta
0.5
1
0
Number

PLOT
1332
198
1532
348
histogram preference private
NIL
NIL
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"default" 0.01 1 -16777216 true "" "histogram [preference-private] of women"

PLOT
1393
393
1593
543
histogram wage
NIL
NIL
0.0
3.0
0.0
1.0
true
false
"" ""
PENS
"default" 0.01 1 -5298144 true "" "histogram [wage] of women"
"pen-1" 0.01 1 -14070903 true "" "histogram [wage] of men"

PLOT
1429
579
1629
729
plot 2
NIL
NIL
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"default" 0.01 1 -16777216 true "" "histogram [conformism] of women"

SWITCH
111
91
236
124
output-locations
output-locations
1
1
-1000

INPUTBOX
606
661
761
721
weight-working-time-self
1.0
1
0
Number

INPUTBOX
606
788
761
848
weight-working-time-partner
1.0
1
0
Number

INPUTBOX
606
726
761
786
weight-transfer
1.0
1
0
Number

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
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

female
false
0
Circle -7500403 false true 88 28 122
Line -7500403 true 150 150 150 225
Line -7500403 true 120 195 180 195

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

male
false
0
Circle -7500403 false true 96 96 108
Line -7500403 true 195 120 255 75
Line -7500403 true 210 75 255 75
Line -7500403 true 240 120 255 75

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

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

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

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment_1" repetitions="1" runMetricsEveryStep="false">
    <setup>setup
ask men
[
set preference-private (1 - preference-private-mean-female)
]</setup>
    <go>go</go>
    <timeLimit steps="10"/>
    <metric>mean [current-utility] of men</metric>
    <metric>mean [current-utility] of women</metric>
    <metric>mean [current-working-time] of men</metric>
    <metric>mean [current-working-time] of women</metric>
    <metric>mean [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>median [current-utility] of women</metric>
    <metric>median [current-working-time] of men</metric>
    <metric>median [current-working-time] of women</metric>
    <metric>median [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <enumeratedValueSet variable="random-seed-fixed">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-structure">
      <value value="&quot;none&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-female-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-female-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-male-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-female-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="wage-female" first="0.1" step="0.01" last="2"/>
    <enumeratedValueSet variable="conformism-female">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-mean-female">
      <value value="0.2"/>
      <value value="0.5"/>
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-mean-male">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CES_beta">
      <value value="-1"/>
      <value value="-0.5"/>
      <value value="0.01"/>
      <value value="0.5"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-network-prob">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="std-dev-values">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="specific-couple">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="import-csv">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-male">
      <value value="80"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="utility-function">
      <value value="&quot;CES&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-neighbors">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-rewiring">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-female">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preferential-attachment-min-degree">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fixed-rs">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-transfer">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-agents-each-type">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="output-locations">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-transfer">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-self">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-partner">
      <value value="1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_2" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>mean [current-utility] of men</metric>
    <metric>mean [current-utility] of women</metric>
    <metric>mean [current-working-time] of men</metric>
    <metric>mean [current-working-time] of women</metric>
    <metric>mean [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>median [current-utility] of women</metric>
    <metric>median [current-working-time] of men</metric>
    <metric>median [current-working-time] of women</metric>
    <metric>median [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>standard-deviation [current-utility] of women</metric>
    <metric>standard-deviation [current-working-time] of men</metric>
    <metric>standard-deviation [current-working-time] of women</metric>
    <metric>standard-deviation [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 25 [current-utility] of women</metric>
    <metric>calc-pct 25 [current-working-time] of men</metric>
    <metric>calc-pct 25 [current-working-time] of women</metric>
    <metric>calc-pct 25 [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 75 [current-utility] of women</metric>
    <metric>calc-pct 75 [current-working-time] of men</metric>
    <metric>calc-pct 75 [current-working-time] of women</metric>
    <metric>calc-pct 75 [current-transfer-to-woman] of women</metric>
    <metric>mean [current-working-time] of women-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of women-with-below-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-below-median-wage-rate</metric>
    <steppedValueSet variable="random-seed-fixed" first="1" step="1" last="1000"/>
    <enumeratedValueSet variable="network-structure">
      <value value="&quot;preference-private&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CES_beta">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-female-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-female-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-male-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-female-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="wage-female" first="0.75" step="0.25" last="1.25"/>
    <enumeratedValueSet variable="conformism-female">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-network-prob">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="std-dev-values">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="specific-couple">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="import-csv">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-male">
      <value value="80"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="utility-function">
      <value value="&quot;CES&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-neighbors">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-rewiring">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-female">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preferential-attachment-min-degree">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fixed-rs">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-transfer">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-agents-each-type">
      <value value="401"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="output-locations">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-transfer">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-self">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-partner">
      <value value="1"/>
    </enumeratedValueSet>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.5"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.5"/>
      </enumeratedValueSet>
    </subExperiment>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.25"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.75"/>
      </enumeratedValueSet>
    </subExperiment>
  </experiment>
  <experiment name="experiment_3" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>mean [current-utility] of men</metric>
    <metric>mean [current-utility] of women</metric>
    <metric>mean [current-working-time] of men</metric>
    <metric>mean [current-working-time] of women</metric>
    <metric>mean [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>median [current-utility] of women</metric>
    <metric>median [current-working-time] of men</metric>
    <metric>median [current-working-time] of women</metric>
    <metric>median [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>standard-deviation [current-utility] of women</metric>
    <metric>standard-deviation [current-working-time] of men</metric>
    <metric>standard-deviation [current-working-time] of women</metric>
    <metric>standard-deviation [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 25 [current-utility] of women</metric>
    <metric>calc-pct 25 [current-working-time] of men</metric>
    <metric>calc-pct 25 [current-working-time] of women</metric>
    <metric>calc-pct 25 [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 75 [current-utility] of women</metric>
    <metric>calc-pct 75 [current-working-time] of men</metric>
    <metric>calc-pct 75 [current-working-time] of women</metric>
    <metric>calc-pct 75 [current-transfer-to-woman] of women</metric>
    <metric>mean [current-working-time] of women-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of women-with-below-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-below-median-wage-rate</metric>
    <steppedValueSet variable="random-seed-fixed" first="1" step="1" last="1000"/>
    <enumeratedValueSet variable="network-structure">
      <value value="&quot;random-network&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-female-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CES_beta">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-female-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-male-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-female-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="wage-female" first="0.75" step="0.25" last="1.25"/>
    <enumeratedValueSet variable="conformism-female">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-network-prob">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="std-dev-values">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="specific-couple">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="import-csv">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-male">
      <value value="80"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="utility-function">
      <value value="&quot;CES&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-neighbors">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-rewiring">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-female">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preferential-attachment-min-degree">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fixed-rs">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-transfer">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-agents-each-type">
      <value value="401"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="output-locations">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-transfer">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-self">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-partner">
      <value value="1"/>
    </enumeratedValueSet>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.5"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.5"/>
      </enumeratedValueSet>
    </subExperiment>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.25"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.75"/>
      </enumeratedValueSet>
    </subExperiment>
  </experiment>
  <experiment name="experiment_4" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>mean [current-utility] of men</metric>
    <metric>mean [current-utility] of women</metric>
    <metric>mean [current-working-time] of men</metric>
    <metric>mean [current-working-time] of women</metric>
    <metric>mean [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>median [current-utility] of women</metric>
    <metric>median [current-working-time] of men</metric>
    <metric>median [current-working-time] of women</metric>
    <metric>median [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>standard-deviation [current-utility] of women</metric>
    <metric>standard-deviation [current-working-time] of men</metric>
    <metric>standard-deviation [current-working-time] of women</metric>
    <metric>standard-deviation [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 25 [current-utility] of women</metric>
    <metric>calc-pct 25 [current-working-time] of men</metric>
    <metric>calc-pct 25 [current-working-time] of women</metric>
    <metric>calc-pct 25 [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 75 [current-utility] of women</metric>
    <metric>calc-pct 75 [current-working-time] of men</metric>
    <metric>calc-pct 75 [current-working-time] of women</metric>
    <metric>calc-pct 75 [current-transfer-to-woman] of women</metric>
    <metric>mean [current-working-time] of women-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of women-with-below-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-below-median-wage-rate</metric>
    <steppedValueSet variable="random-seed-fixed" first="1" step="1" last="1000"/>
    <enumeratedValueSet variable="network-structure">
      <value value="&quot;watts-strogatz&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CES_beta">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-female-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-female-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-male-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-female-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="wage-female" first="0.75" step="0.25" last="1.25"/>
    <enumeratedValueSet variable="conformism-female">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-network-prob">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="std-dev-values">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="specific-couple">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="import-csv">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-male">
      <value value="80"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="utility-function">
      <value value="&quot;CES&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-neighbors">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-rewiring">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-female">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preferential-attachment-min-degree">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fixed-rs">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-transfer">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-agents-each-type">
      <value value="401"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="output-locations">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-transfer">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-self">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-partner">
      <value value="1"/>
    </enumeratedValueSet>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.5"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.5"/>
      </enumeratedValueSet>
    </subExperiment>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.25"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.75"/>
      </enumeratedValueSet>
    </subExperiment>
  </experiment>
  <experiment name="experiment_5" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>mean [current-utility] of men</metric>
    <metric>mean [current-utility] of women</metric>
    <metric>mean [current-working-time] of men</metric>
    <metric>mean [current-working-time] of women</metric>
    <metric>mean [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>median [current-utility] of women</metric>
    <metric>median [current-working-time] of men</metric>
    <metric>median [current-working-time] of women</metric>
    <metric>median [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>standard-deviation [current-utility] of women</metric>
    <metric>standard-deviation [current-working-time] of men</metric>
    <metric>standard-deviation [current-working-time] of women</metric>
    <metric>standard-deviation [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 25 [current-utility] of women</metric>
    <metric>calc-pct 25 [current-working-time] of men</metric>
    <metric>calc-pct 25 [current-working-time] of women</metric>
    <metric>calc-pct 25 [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 75 [current-utility] of women</metric>
    <metric>calc-pct 75 [current-working-time] of men</metric>
    <metric>calc-pct 75 [current-working-time] of women</metric>
    <metric>calc-pct 75 [current-transfer-to-woman] of women</metric>
    <metric>mean [current-working-time] of women-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of women-with-below-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-below-median-wage-rate</metric>
    <steppedValueSet variable="random-seed-fixed" first="1" step="1" last="1000"/>
    <enumeratedValueSet variable="network-structure">
      <value value="&quot;preferential-attachment&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CES_beta">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-female-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-female-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-male-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-female-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="wage-female" first="0.75" step="0.25" last="1.25"/>
    <enumeratedValueSet variable="conformism-female">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-network-prob">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="std-dev-values">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="specific-couple">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="import-csv">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-male">
      <value value="80"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="utility-function">
      <value value="&quot;CES&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-neighbors">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-rewiring">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-female">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preferential-attachment-min-degree">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fixed-rs">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-transfer">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-agents-each-type">
      <value value="401"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="output-locations">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-transfer">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-self">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-partner">
      <value value="1"/>
    </enumeratedValueSet>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.5"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.5"/>
      </enumeratedValueSet>
    </subExperiment>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.25"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.75"/>
      </enumeratedValueSet>
    </subExperiment>
  </experiment>
  <experiment name="experiment_6" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>mean [current-utility] of men</metric>
    <metric>mean [current-utility] of women</metric>
    <metric>mean [current-working-time] of men</metric>
    <metric>mean [current-working-time] of women</metric>
    <metric>mean [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>median [current-utility] of women</metric>
    <metric>median [current-working-time] of men</metric>
    <metric>median [current-working-time] of women</metric>
    <metric>median [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>standard-deviation [current-utility] of women</metric>
    <metric>standard-deviation [current-working-time] of men</metric>
    <metric>standard-deviation [current-working-time] of women</metric>
    <metric>standard-deviation [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 25 [current-utility] of women</metric>
    <metric>calc-pct 25 [current-working-time] of men</metric>
    <metric>calc-pct 25 [current-working-time] of women</metric>
    <metric>calc-pct 25 [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 75 [current-utility] of women</metric>
    <metric>calc-pct 75 [current-working-time] of men</metric>
    <metric>calc-pct 75 [current-working-time] of women</metric>
    <metric>calc-pct 75 [current-transfer-to-woman] of women</metric>
    <metric>mean [current-working-time] of women-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of women-with-below-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-below-median-wage-rate</metric>
    <steppedValueSet variable="random-seed-fixed" first="1" step="1" last="1000"/>
    <enumeratedValueSet variable="network-structure">
      <value value="&quot;conformism&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CES_beta">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-female-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-female-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-male-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-female-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="wage-female" first="0.75" step="0.25" last="1.25"/>
    <enumeratedValueSet variable="conformism-female">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-network-prob">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="std-dev-values">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="specific-couple">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="import-csv">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-male">
      <value value="80"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="utility-function">
      <value value="&quot;CES&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-neighbors">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-rewiring">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-female">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preferential-attachment-min-degree">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fixed-rs">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-transfer">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-agents-each-type">
      <value value="401"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="output-locations">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-transfer">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-self">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-partner">
      <value value="1"/>
    </enumeratedValueSet>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.5"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.5"/>
      </enumeratedValueSet>
    </subExperiment>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.25"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.75"/>
      </enumeratedValueSet>
    </subExperiment>
  </experiment>
  <experiment name="experiment_7" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>mean [current-utility] of men</metric>
    <metric>mean [current-utility] of women</metric>
    <metric>mean [current-working-time] of men</metric>
    <metric>mean [current-working-time] of women</metric>
    <metric>mean [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>median [current-utility] of women</metric>
    <metric>median [current-working-time] of men</metric>
    <metric>median [current-working-time] of women</metric>
    <metric>median [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>standard-deviation [current-utility] of women</metric>
    <metric>standard-deviation [current-working-time] of men</metric>
    <metric>standard-deviation [current-working-time] of women</metric>
    <metric>standard-deviation [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 25 [current-utility] of women</metric>
    <metric>calc-pct 25 [current-working-time] of men</metric>
    <metric>calc-pct 25 [current-working-time] of women</metric>
    <metric>calc-pct 25 [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 75 [current-utility] of women</metric>
    <metric>calc-pct 75 [current-working-time] of men</metric>
    <metric>calc-pct 75 [current-working-time] of women</metric>
    <metric>calc-pct 75 [current-transfer-to-woman] of women</metric>
    <metric>mean [current-working-time] of women-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of women-with-below-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-below-median-wage-rate</metric>
    <steppedValueSet variable="random-seed-fixed" first="1" step="1" last="1000"/>
    <enumeratedValueSet variable="network-structure">
      <value value="&quot;wage&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CES_beta">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-female-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-female-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-male-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-female-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="wage-female" first="0.75" step="0.25" last="1.25"/>
    <enumeratedValueSet variable="conformism-female">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-network-prob">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="std-dev-values">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="specific-couple">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="import-csv">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-male">
      <value value="80"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="utility-function">
      <value value="&quot;CES&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-neighbors">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-rewiring">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-female">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preferential-attachment-min-degree">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fixed-rs">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-transfer">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-agents-each-type">
      <value value="401"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="output-locations">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-transfer">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-self">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-partner">
      <value value="1"/>
    </enumeratedValueSet>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.5"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.5"/>
      </enumeratedValueSet>
    </subExperiment>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.25"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.75"/>
      </enumeratedValueSet>
    </subExperiment>
  </experiment>
  <experiment name="experiment_8" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>mean [current-utility] of men</metric>
    <metric>mean [current-utility] of women</metric>
    <metric>mean [current-working-time] of men</metric>
    <metric>mean [current-working-time] of women</metric>
    <metric>mean [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>median [current-utility] of women</metric>
    <metric>median [current-working-time] of men</metric>
    <metric>median [current-working-time] of women</metric>
    <metric>median [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>standard-deviation [current-utility] of women</metric>
    <metric>standard-deviation [current-working-time] of men</metric>
    <metric>standard-deviation [current-working-time] of women</metric>
    <metric>standard-deviation [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 25 [current-utility] of women</metric>
    <metric>calc-pct 25 [current-working-time] of men</metric>
    <metric>calc-pct 25 [current-working-time] of women</metric>
    <metric>calc-pct 25 [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 75 [current-utility] of women</metric>
    <metric>calc-pct 75 [current-working-time] of men</metric>
    <metric>calc-pct 75 [current-working-time] of women</metric>
    <metric>calc-pct 75 [current-transfer-to-woman] of women</metric>
    <metric>mean [current-working-time] of women-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of women-with-below-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-below-median-wage-rate</metric>
    <steppedValueSet variable="random-seed-fixed" first="1" step="1" last="1000"/>
    <enumeratedValueSet variable="network-structure">
      <value value="&quot;none&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CES_beta">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-female-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-female-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-male-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-female-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="wage-female" first="0.75" step="0.25" last="1.25"/>
    <enumeratedValueSet variable="conformism-female">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-network-prob">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="std-dev-values">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="specific-couple">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="import-csv">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-male">
      <value value="80"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="utility-function">
      <value value="&quot;CES&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-neighbors">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-rewiring">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-female">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preferential-attachment-min-degree">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fixed-rs">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-transfer">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-agents-each-type">
      <value value="401"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="output-locations">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-transfer">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-self">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-partner">
      <value value="1"/>
    </enumeratedValueSet>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.5"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.5"/>
      </enumeratedValueSet>
    </subExperiment>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.25"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.75"/>
      </enumeratedValueSet>
    </subExperiment>
  </experiment>
  <experiment name="experiment_9" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>mean [current-utility] of men</metric>
    <metric>mean [current-utility] of women</metric>
    <metric>mean [current-working-time] of men</metric>
    <metric>mean [current-working-time] of women</metric>
    <metric>mean [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>median [current-utility] of women</metric>
    <metric>median [current-working-time] of men</metric>
    <metric>median [current-working-time] of women</metric>
    <metric>median [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>standard-deviation [current-utility] of women</metric>
    <metric>standard-deviation [current-working-time] of men</metric>
    <metric>standard-deviation [current-working-time] of women</metric>
    <metric>standard-deviation [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 25 [current-utility] of women</metric>
    <metric>calc-pct 25 [current-working-time] of men</metric>
    <metric>calc-pct 25 [current-working-time] of women</metric>
    <metric>calc-pct 25 [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 75 [current-utility] of women</metric>
    <metric>calc-pct 75 [current-working-time] of men</metric>
    <metric>calc-pct 75 [current-working-time] of women</metric>
    <metric>calc-pct 75 [current-transfer-to-woman] of women</metric>
    <metric>mean [current-working-time] of women-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of women-with-below-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-below-median-wage-rate</metric>
    <steppedValueSet variable="random-seed-fixed" first="1" step="1" last="1000"/>
    <enumeratedValueSet variable="network-structure">
      <value value="&quot;homogenous mixing&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CES_beta">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-female-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-female-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-male-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-female-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="wage-female" first="0.75" step="0.25" last="1.25"/>
    <enumeratedValueSet variable="conformism-female">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-network-prob">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="std-dev-values">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="specific-couple">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="import-csv">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-male">
      <value value="80"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="utility-function">
      <value value="&quot;CES&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-neighbors">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-rewiring">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-female">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preferential-attachment-min-degree">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fixed-rs">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-transfer">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-agents-each-type">
      <value value="401"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="output-locations">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-transfer">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-self">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-partner">
      <value value="1"/>
    </enumeratedValueSet>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.5"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.5"/>
      </enumeratedValueSet>
    </subExperiment>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.25"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.75"/>
      </enumeratedValueSet>
    </subExperiment>
  </experiment>
  <experiment name="different_conformism" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="100"/>
    <metric>mean [current-utility] of men</metric>
    <metric>mean [current-utility] of women</metric>
    <metric>mean [current-working-time] of men</metric>
    <metric>mean [current-working-time] of women</metric>
    <metric>mean [current-transfer-to-woman] of women</metric>
    <metric>average-mean-working-time-women</metric>
    <metric>average-mean-working-time-men</metric>
    <enumeratedValueSet variable="std-dev-values">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="import-csv">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CES_beta">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-male">
      <value value="80"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-neighbors">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-female-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-female">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-female-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-mean-male">
      <value value="0.5"/>
    </enumeratedValueSet>
    <steppedValueSet variable="conformism-male" first="0" step="0.1" last="5"/>
    <enumeratedValueSet variable="wage-female">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preferential-attachment-min-degree">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-male-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-mean-female">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-transfer">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-network-prob">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="specific-couple">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-female-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-seed-fixed">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="utility-function">
      <value value="&quot;CES&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-rewiring">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-structure">
      <value value="&quot;none&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fixed-rs">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-agents-each-type">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="conformism-female" first="0" step="0.1" last="5"/>
    <enumeratedValueSet variable="output-locations">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-transfer">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-self">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-partner">
      <value value="1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_10" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>mean [current-utility] of men</metric>
    <metric>mean [current-utility] of women</metric>
    <metric>mean [current-working-time] of men</metric>
    <metric>mean [current-working-time] of women</metric>
    <metric>mean [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>median [current-utility] of women</metric>
    <metric>median [current-working-time] of men</metric>
    <metric>median [current-working-time] of women</metric>
    <metric>median [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>standard-deviation [current-utility] of women</metric>
    <metric>standard-deviation [current-working-time] of men</metric>
    <metric>standard-deviation [current-working-time] of women</metric>
    <metric>standard-deviation [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 25 [current-utility] of women</metric>
    <metric>calc-pct 25 [current-working-time] of men</metric>
    <metric>calc-pct 25 [current-working-time] of women</metric>
    <metric>calc-pct 25 [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 75 [current-utility] of women</metric>
    <metric>calc-pct 75 [current-working-time] of men</metric>
    <metric>calc-pct 75 [current-working-time] of women</metric>
    <metric>calc-pct 75 [current-transfer-to-woman] of women</metric>
    <metric>mean [current-working-time] of women-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of women-with-below-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-below-median-wage-rate</metric>
    <steppedValueSet variable="random-seed-fixed" first="1" step="1" last="1000"/>
    <enumeratedValueSet variable="network-structure">
      <value value="&quot;random-network&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-female-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CES_beta">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-female-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-male-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-female-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-female">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-female">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-network-prob">
      <value value="0.02"/>
      <value value="0.05"/>
      <value value="0.1"/>
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="std-dev-values">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="specific-couple">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="import-csv">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-male">
      <value value="80"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="utility-function">
      <value value="&quot;CES&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-neighbors">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-rewiring">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-female">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preferential-attachment-min-degree">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fixed-rs">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-transfer">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-agents-each-type">
      <value value="401"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="output-locations">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-transfer">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-self">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-partner">
      <value value="1"/>
    </enumeratedValueSet>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.5"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.5"/>
      </enumeratedValueSet>
    </subExperiment>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.25"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.75"/>
      </enumeratedValueSet>
    </subExperiment>
  </experiment>
  <experiment name="experiment_11" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>mean [current-utility] of men</metric>
    <metric>mean [current-utility] of women</metric>
    <metric>mean [current-working-time] of men</metric>
    <metric>mean [current-working-time] of women</metric>
    <metric>mean [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>median [current-utility] of women</metric>
    <metric>median [current-working-time] of men</metric>
    <metric>median [current-working-time] of women</metric>
    <metric>median [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>standard-deviation [current-utility] of women</metric>
    <metric>standard-deviation [current-working-time] of men</metric>
    <metric>standard-deviation [current-working-time] of women</metric>
    <metric>standard-deviation [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 25 [current-utility] of women</metric>
    <metric>calc-pct 25 [current-working-time] of men</metric>
    <metric>calc-pct 25 [current-working-time] of women</metric>
    <metric>calc-pct 25 [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 75 [current-utility] of women</metric>
    <metric>calc-pct 75 [current-working-time] of men</metric>
    <metric>calc-pct 75 [current-working-time] of women</metric>
    <metric>calc-pct 75 [current-transfer-to-woman] of women</metric>
    <metric>mean [current-working-time] of women-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of women-with-below-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-below-median-wage-rate</metric>
    <steppedValueSet variable="random-seed-fixed" first="1" step="1" last="1000"/>
    <enumeratedValueSet variable="network-structure">
      <value value="&quot;homogenous mixing&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CES_beta">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-female-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-female-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-male-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-female-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="wage-female" first="0.75" step="0.25" last="1.25"/>
    <enumeratedValueSet variable="conformism-female">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-network-prob">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="std-dev-values">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="specific-couple">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="import-csv">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-male">
      <value value="80"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="utility-function">
      <value value="&quot;CES&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-neighbors">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-rewiring">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-female">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preferential-attachment-min-degree">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fixed-rs">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-transfer">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-agents-each-type">
      <value value="401"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="output-locations">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-transfer">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-self">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-partner">
      <value value="1"/>
    </enumeratedValueSet>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.5"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.5"/>
      </enumeratedValueSet>
    </subExperiment>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.25"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.75"/>
      </enumeratedValueSet>
    </subExperiment>
  </experiment>
  <experiment name="experiment_12" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>mean [current-utility] of men</metric>
    <metric>mean [current-utility] of women</metric>
    <metric>mean [current-working-time] of men</metric>
    <metric>mean [current-working-time] of women</metric>
    <metric>mean [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>median [current-utility] of women</metric>
    <metric>median [current-working-time] of men</metric>
    <metric>median [current-working-time] of women</metric>
    <metric>median [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>standard-deviation [current-utility] of women</metric>
    <metric>standard-deviation [current-working-time] of men</metric>
    <metric>standard-deviation [current-working-time] of women</metric>
    <metric>standard-deviation [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 25 [current-utility] of women</metric>
    <metric>calc-pct 25 [current-working-time] of men</metric>
    <metric>calc-pct 25 [current-working-time] of women</metric>
    <metric>calc-pct 25 [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 75 [current-utility] of women</metric>
    <metric>calc-pct 75 [current-working-time] of men</metric>
    <metric>calc-pct 75 [current-working-time] of women</metric>
    <metric>calc-pct 75 [current-transfer-to-woman] of women</metric>
    <metric>mean [current-working-time] of women-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-high-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of men-in-low-public-goods-preference-households</metric>
    <metric>mean [current-working-time] of women-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-above-median-wage-rate</metric>
    <metric>mean [current-working-time] of women-with-below-median-wage-rate</metric>
    <metric>mean [current-working-time] of men-with-below-median-wage-rate</metric>
    <steppedValueSet variable="random-seed-fixed" first="1" step="1" last="1000"/>
    <enumeratedValueSet variable="network-structure">
      <value value="&quot;homophily&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CES_beta">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-female-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-female-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-male-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-female-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="wage-female" first="0.75" step="0.25" last="1.25"/>
    <enumeratedValueSet variable="conformism-female">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-network-prob">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="std-dev-values">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="specific-couple">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="import-csv">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-male">
      <value value="80"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="utility-function">
      <value value="&quot;CES&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-neighbors">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-rewiring">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-female">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preferential-attachment-min-degree">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fixed-rs">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-transfer">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-agents-each-type">
      <value value="401"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="output-locations">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-transfer">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-self">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-partner">
      <value value="1"/>
    </enumeratedValueSet>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.5"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.5"/>
      </enumeratedValueSet>
    </subExperiment>
    <subExperiment>
      <enumeratedValueSet variable="preference-private-mean-female">
        <value value="0.25"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="preference-private-mean-male">
        <value value="0.75"/>
      </enumeratedValueSet>
    </subExperiment>
  </experiment>
  <experiment name="print positions" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <postRun>file-close-all</postRun>
    <timeLimit steps="50"/>
    <metric>mean [current-utility] of men</metric>
    <metric>mean [current-utility] of women</metric>
    <metric>mean [current-working-time] of men</metric>
    <metric>mean [current-working-time] of women</metric>
    <metric>mean [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>median [current-utility] of women</metric>
    <metric>median [current-working-time] of men</metric>
    <metric>median [current-working-time] of women</metric>
    <metric>median [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>standard-deviation [current-utility] of women</metric>
    <metric>standard-deviation [current-working-time] of men</metric>
    <metric>standard-deviation [current-working-time] of women</metric>
    <metric>standard-deviation [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 25 [current-utility] of women</metric>
    <metric>calc-pct 25 [current-working-time] of men</metric>
    <metric>calc-pct 25 [current-working-time] of women</metric>
    <metric>calc-pct 25 [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 75 [current-utility] of women</metric>
    <metric>calc-pct 75 [current-working-time] of men</metric>
    <metric>calc-pct 75 [current-working-time] of women</metric>
    <metric>calc-pct 75 [current-transfer-to-woman] of women</metric>
    <enumeratedValueSet variable="random-seed-fixed">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-structure">
      <value value="&quot;preference-private&quot;"/>
      <value value="&quot;random-network&quot;"/>
      <value value="&quot;watts-strogatz&quot;"/>
      <value value="&quot;preferential-attachment&quot;"/>
      <value value="&quot;wage&quot;"/>
      <value value="&quot;conformism&quot;"/>
      <value value="&quot;homogenous mixing&quot;"/>
      <value value="&quot;homophily&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CES_beta">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-female-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-female-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-male-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-female-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-female">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-female">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-mean-female">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-mean-male">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-network-prob">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="std-dev-values">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="specific-couple">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="import-csv">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-male">
      <value value="80"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="utility-function">
      <value value="&quot;CES&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-neighbors">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-rewiring">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-female">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preferential-attachment-min-degree">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fixed-rs">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-transfer">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-agents-each-type">
      <value value="401"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="output-locations">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-transfer">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-self">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-partner">
      <value value="1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="print positions2" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <postRun>file-close-all</postRun>
    <timeLimit steps="50"/>
    <metric>mean [current-utility] of men</metric>
    <metric>mean [current-utility] of women</metric>
    <metric>mean [current-working-time] of men</metric>
    <metric>mean [current-working-time] of women</metric>
    <metric>mean [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>median [current-utility] of women</metric>
    <metric>median [current-working-time] of men</metric>
    <metric>median [current-working-time] of women</metric>
    <metric>median [current-transfer-to-woman] of women</metric>
    <metric>median [current-utility] of men</metric>
    <metric>standard-deviation [current-utility] of women</metric>
    <metric>standard-deviation [current-working-time] of men</metric>
    <metric>standard-deviation [current-working-time] of women</metric>
    <metric>standard-deviation [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 25 [current-utility] of women</metric>
    <metric>calc-pct 25 [current-working-time] of men</metric>
    <metric>calc-pct 25 [current-working-time] of women</metric>
    <metric>calc-pct 25 [current-transfer-to-woman] of women</metric>
    <metric>calc-pct 75 [current-utility] of women</metric>
    <metric>calc-pct 75 [current-working-time] of men</metric>
    <metric>calc-pct 75 [current-working-time] of women</metric>
    <metric>calc-pct 75 [current-transfer-to-woman] of women</metric>
    <enumeratedValueSet variable="random-seed-fixed">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-structure">
      <value value="&quot;homogenous mixing&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CES_beta">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-female-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-female-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-male-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-female-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-female">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-female">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-mean-female">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-mean-male">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-network-prob">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="std-dev-values">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="specific-couple">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="import-csv">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-male">
      <value value="80"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="utility-function">
      <value value="&quot;CES&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-neighbors">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-rewiring">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-female">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preferential-attachment-min-degree">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fixed-rs">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-transfer">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-agents-each-type">
      <value value="401"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="output-locations">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-transfer">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-self">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="weight-working-time-partner">
      <value value="1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="different_conformism2" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="100"/>
    <metric>mean [current-utility] of men</metric>
    <metric>mean [current-utility] of women</metric>
    <metric>mean [current-working-time] of men</metric>
    <metric>mean [current-working-time] of women</metric>
    <metric>mean [current-transfer-to-woman] of women</metric>
    <metric>average-mean-working-time-women</metric>
    <metric>average-mean-working-time-men</metric>
    <enumeratedValueSet variable="std-dev-values">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="import-csv">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="CES_beta">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-male">
      <value value="80"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-neighbors">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-female-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="norm-paid-time-female">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-female-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-mean-male">
      <value value="0.5"/>
    </enumeratedValueSet>
    <steppedValueSet variable="conformism-male" first="0" step="0.1" last="5"/>
    <enumeratedValueSet variable="wage-female">
      <value value="0.75"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preferential-attachment-min-degree">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-male-in-question">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="preference-private-mean-female">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male-in-question">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-transfer">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-network-prob">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="specific-couple">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-female-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="conformism-male-in-question">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="random-seed-fixed">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="utility-function">
      <value value="&quot;CES&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="watts-strogatz-rewiring">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="network-structure">
      <value value="&quot;none&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fixed-rs">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-agents-each-type">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wage-male">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="conformism-female" first="0" step="0.1" last="5"/>
    <enumeratedValueSet variable="output-locations">
      <value value="false"/>
    </enumeratedValueSet>
    <steppedValueSet variable="weight-transfer" first="0" step="0.5" last="1"/>
    <steppedValueSet variable="weight-working-time-self" first="0" step="0.5" last="1"/>
    <steppedValueSet variable="weight-working-time-partner" first="0" step="0.5" last="1"/>
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
@#$#@#$#@
0
@#$#@#$#@
