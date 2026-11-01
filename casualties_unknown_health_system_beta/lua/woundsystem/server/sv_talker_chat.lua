if WoundSystem and WoundSystem.TalkerChatLoaded then
    hook.Remove("PlayerSay", "WoundSystem_TalkerChatEffects")
    hook.Remove("PlayerDisconnected", "WoundSystem_TalkerSelfTalkCleanup")
    hook.Remove("EntityTakeDamage", "WoundSystem_TalkerHitByCreature")
    timer.Remove("WoundSystem_TalkerSelfTalk")
end

WoundSystem = WoundSystem or {}
WoundSystem.TalkerChatLoaded = true

util.AddNetworkString("WoundSystem_SelfTalkChat")

local function WoundSystemHealthEnabled()
    local config = WoundSystem and WoundSystem.Health and WoundSystem.Health.Config
    if config and config.IsEnabled then
        return config.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

local SELF_TALK_INTERVAL = 2
local SELF_TALK_DEFAULT = 1
local COMMAND_PREFIXES = {
    ["/"] = true,
    ["!"] = true,
    ["."] = true,
    ["@"] = true
}

local FULL_MOUTH_CHARS = {"m", "n", "o", "a", "e"}
local UNDERWATER_CHARS = {"b", "l", "u", "g"}
local SelfTalkState = {}

local LIMB_NAMES = {
    head = "head",
    thorax = "chest",
    abdomen = "abdomen",
    arm_R = "right arm",
    forearm_R = "right forearm",
    hand_R = "right hand",
    arm_L = "left arm",
    forearm_L = "left forearm",
    hand_L = "left hand",
    thigh_R = "right thigh",
    crus_R = "right leg",
    foot_R = "right foot",
    thigh_L = "left thigh",
    crus_L = "left leg",
    foot_L = "left foot"
}

local TALK_LINES = {
    seeGravel = {
        "We're here...",
        "Okay... Let's do this.",
        "I'm ready...",
        "I didn't want to do this...",
        "Let's go.",
        "Alright. Let's move fast.",
        "Ooh!",
        "This looks... Grayer than I anticipated.",
        "How... Gray.",
        "I'm not ready for this...",
        "I hope this'll go well.",
        "'Kay. I need to go... down. Straight down.",
        "Looks scary.",
        "Where am I now...?",
        "I'm not sure about this...",
        "...Hmmh...",
        "Alright...",
        "Let's move. Quickly.",
        "That's a cave alright.",
        "Aye! Let's not waste any time.",
        "They really didn't leave anything in my pod...",
        "My pod really is empty...",
        "Let's step outside.",
        "*worried frown*",
        "I'm excited!",
        "Not excited for this.",
        "Better here than there...",
        "At least I had food and shelter up there...",
        "I'm already missing my peers from up there.",
        "I don't think they can monitor me down here... Right...?",
        "I have to go... Down. Straight down.",
        "Let's go deep.",
        "Awwa...?",
        "Hmm...",
        "Welp. I guess that's it.",
        "Aaannd we've arrived!",
        "I hope I'll get to see my friends again.",
        "HELLO!? IS ANYONE HERE!?",
        "It's nice not seeing white tiles around for once...",
        "At least I'm alive...",
        "My ride's over.",
        "..Mm. What a peculiar landscape...",
        "Let's hope I remember my training...",
        "I'm already missing my friends...",
        "My parent would be proud...",
        "Wow! ...Gray.",
        "Looks gravelly.",
        "Haven't seen those open in a while.",
        "God. This is going to be fucking horrible.",
        "This is gonna be fun.",
        "Go down... Get the thing if I find it... Okay...",
    },
    eatGood = {
        "Mmm!",
        "Tasty.",
        "Tasty!",
        "Yum!",
        "Yummy.",
        "Mm...",
        "Neat!",
        "Yummy!",
        "Nice!",
        "Tasty treat...",
        "Delicious bite...",
        "Tastes great.",
        "Satisfying...",
        "That's the stuff...",
        "Fueling up...",
        "Yummy...",
        "That's pretty good...",
        "Not bad!...",
        "Yummers...",
        "Good for me...",
        "Mmmmm...",
        "Never enough of that...",
        "Yum! I feel better!",
        "Nom nom nom.",
        "That was amazing!",
        "Such good flavor...",
        "Flavourful!",
        "Enjoying this...",
        "More of this...",
        "Good food...",
        "Love this taste...",
        "Delicious...",
        "Mmm, nice...",
        "Just what I needed...",
        "Mmmmm...",
    },
    eatMediocre = {
        "Ehh...",
        "I've eaten better...",
        "...",
        "What is this?",
        "Mhh...",
        "Gh..",
        "...?",
        "Okay...",
        "...Ew.",
        "Meh...",
        "This texture...",
        "This taste...",
        "Guh!",
        "Ugh...",
        "Really?",
        "Could be better.",
        "Tastes... acceptable.",
        "Not impressive...",
        "Mhh...",
        "Hmph.",
        "Plehh... Bland.",
        "Pleh.",
        "Good enough.",
        "Eeehh...",
        "Not great.",
        "What is this?",
        "Blah...",
        "Hmm...",
        "Meh.",
        "So-so...",
        "Eh...",
        "Meh.",
        "?",
    },
    eatBad = {
        "Ew!",
        "Ack! What is this!",
        "Yuck!",
        "I think I'm gonna be sick...",
        "Why am I eating this!?",
        "I'd rather starve.",
        "I'd genuinely rather starve.",
        "Is this some sort of punishment...?",
        "This is unacceptable.",
        "Do I really have to eat this? Ugh.",
        "Ack! It tastes so bad!",
        "Ew ew ew! Uugh!",
        "That tasted terrible!",
        "I don't want to eat that ever again.",
        "Uugh! Gross!",
        "Yuck! Get it out of my mouth!",
        "That was the worst!",
        "Gross! Never again!",
        "That tastes like SHIT!",
        "This might make me throw up...",
        "That tasted BAD!",
        "Out of my mouth! Uugh!",
        "This SUCKS!",
        "Ewww!!",
        "Yucky!!!",
        "This tastes rotten!",
        "I HATE that taste!",
        "That's disgusting...",
        "Ew.",
        "This 'food' is upsetting.",
        "This is upsetting.",
        "Oouugh! No! Ew!",
        "Disgusting!",
        "I didn't want to eat this.",
        "What the FUCK am I EATING!?",
    },
    refuseEat = {
        "I'm not eating this.",
        "I'm genuinely not eating this.",
        "No.",
        "Keep that away from me.",
        "Why would I touch this!?",
        "No!",
        "Why am I even holding this?",
        "Not in a million years.",
        "I would never! NO!",
        "What the hell am I thinking?",
        "No! That's disgusting!",
        "This is disgusting! No!",
        "EW! No!",
        "I'm not putting that IN or ANYWHERE near my mouth.",
        "Don't even think about it.",
        "I'm not letting the intrusive thoughts win.",
        "Ew. Fuck that.",
    },
    tired = {
        "*yawn*",
        "What time is it?",
        "I feel drowsy...",
        "I'm a little tired.",
        "I could go for a nap.",
        "Nap time is coming...",
        "I'm kinda tired.",
        "I'm getting sleepy.",
        "Resting myself sounds nice.",
        "Sleep sounds great right now.",
        "I should rest my head soon.",
        "Nap time...",
        "I'm sleepy.",
        "I need to sleep soon.",
        "Getting rest isn't a bad idea right now...",
        "I need a nice nap.",
        "Mmmm... tired...",
        "Getting a little drowsy.",
        "I kind-of want to lay down.",
        "Could do with a lay-down.",
        "I'm sleepy...",
        "Maybe that's enough for today...?",
        "Sleepy...",
    },
    verytired = {
        "Ughh....",
        "Yyyawwwnnn...",
        "I'm soooo tired...",
        "Ugh... I'm tired...",
        "I want to lay down...",
        "It's hard to keep my eyes open...",
        "I feel like I'm about to fall asleep at any moment...",
        "Sleep...? Please?",
        "I'm going to collapse...",
        "Can't... keep... going...",
        "Buh... sleep...",
        "Need to eep... mmm...",
        "My eyes are closing...",
        "I seriously... need sleep...",
        "I have to... lie down...",
        "My eyes are so heavy...",
        "I can't... see straight...",
        "Just some sleep...",
        "I'm so... worn out...",
        "Can't keep my eyes open...",
        "When can I lay down...",
        "I'm about to fall asleep...",
        "...",
        "So tired...",
        "I'm so sleepy...",
        "Really tired...",
        "Let me rest...",
    },
    confused = {
        "What's happening...?",
        "Ough...",
        "I'm confused...",
        "Where am I...?",
        "Augh...",
        "My head...",
        "I'm gonna pass out...",
        "Uugh... head... hurty...",
        "What's?... Huh?...",
        "What's going... on?...",
        "I'm... barely conscious...",
        "I can't... what is happening?...",
        "Who's... there?...",
        "I can't stand straight...",
        "I swear I... uhh?",
        "Uhhhn.. What's going on?...",
        "Can't get my head straight...",
        "I don't feel right.",
        "Something's... wrong?",
        "Can't focus...",
        "I feel so woozy...",
        "I feel confused...",
        "Huh... I...?",
        "Ngh...",
        "Can't... stay alert...",
        "Stay alert...",
        "...?",
    },
    wakeup = {
        "What's happening...?",
        "Stay alert...",
        "Good morning...",
        "Here we go...",
        "Mmmmhhm...",
        "Alright...",
        "Back to it...",
        "Another day...",
        "Here we go again...",
        "Eyes open...",
        "Awake and alert...",
        "Hello, world...",
        "Again...",
    },
    sick = {
        "My stomach hurts...",
        "I feel sick.",
        "Ouch... My guts hurt.",
        "I feel nauseous.",
        "I'm queasy...",
        "I think I ate something bad...",
        "I don't feel well...",
        "My body isn't doing well.",
        "I need a better diet...",
        "Ough... Nauseous.",
        "I'm sick...",
        "I should watch what I eat...",
        "Ghh... stomach...",
        "I feel ill.",
        "I need to watch what I eat...",
        "My body's aching...",
        "I think I'm falling ill.",
        "I feel bad.",
        "I don't feel well.",
        "My belly hurts.",
        "My stomach feels weird.",
        "I feel like vomiting.",
        "I'm unwell.",
    },
    verysick = {
        "Fuck... My stomach...",
        "I want to vomit...",
        "I'm going to vomit.",
        "My stomach hurts really bad.",
        "My guts are on fire.",
        "I'm... so sick...",
        "I'm so nauseous...",
        "I can't focus at all.",
        "I feel diseased...",
        "I think I'm poisoned..",
        "I ate something really bad.",
        "My stomach...",
        "I feel really unwell.",
        "I want to pass out.",
        "I feel sick to my stomach...",
        "This illness... hurts...",
        "My body is aching so bad...",
        "I want to throw up.",
        "I will throw up...",
        "I think I'm about to vomit...",
        "My abdomen hurts a lot.",
        "I feel terrible.",
        "I'm poisoned.",
        "Fuuuuckk... My stomach...",
    },
    vomit = {
        "Bluughh... uughh...",
        "Ghghh... *cough*",
        "There's my... lunch...",
        "Bllggh... ugh... damn...",
        "Uuggh... that... felt terrible...",
        "That WAS dinner.",
        "Guhhgh... yuck..",
        "Uughh.. ew...",
        "I feel... uhhgh... empty...",
        "Guughhg... hcck... my stomach...",
        "Uuughgh... I'm too... sick...",
        "I can't believe... I'm this sick...",
        "Guuhghh... ughh...",
        "I'm so weak.. gughh...",
        "...uughh... gross...",
        "Ff.... Fuck... ugh...",
        "Wow... just... threw up...",
        "Ghhuhh... empty... stomach...",
        "My body's... revolting...",
        "This isn't... ghghuh... going great...",
        "Fuck me... Ough... Damn it...",
    },
    vomitblood = {
        "Bluughh... I... Oh. Oh god, that's blood...",
        "Ghghh... *cough* ...Fuck... That's... Blood...",
        "There's my... lu... Oh. Oh no no no. Oh no. That's blood I just threw up...",
        "Bllggh... ugh... I... Oh... God...",
        "Is that... Is that blood I just... Blugh...",
        "I'm pretty sure blood isn't supposed to do that.",
        "Guhhgh... Why is my vomit... So yellow...?",
        "Uughh... Something's... Very wrong...",
        "That's... That's not what vomit tastes like... W-wait...",
        "Guughhg... Hic... That... That wasn't from my stomach. Oh... Oh god.",
        "Uuughgh... Help... That's blood I just threw up...",
        "I can't believe... Did I just... Vomit up blood...",
        "Guuhghh... ughh... This is... Bad...",
        "I'm so weak.. gughh... That felt... Very odd...",
        "...uughh... gross- ...Blood. That's blood. I just threw up blood. Oh no. Oh NO.",
        "Ff.... Fuck... ugh... Blood... That can't be good...",
        "Wow... just... threw up... Blood?... ..Huh?",
        "Ghhuhh... Why did I... Just...",
        "I'm... guugh... ...I'm pretty sure that's blood... I'm bleeding on the inside...",
        "This isn't... ghghuh... Vomit... This isn't... Oh...",
        "Fuck me... Ough... Damn it... Not like this...",
    },
    full = {
        "That's enough.",
        "Any more and I'll be sick.",
        "I'm full.",
        "I don't want to eat more.",
        "My belly's full.",
        "My stomach's full.",
        "I can't eat another bite...",
        "I feel like I'm about to burst.",
        "I can't eat any more...",
        "I need to stop eating.",
        "I'm going to gain weight at this point...",
        "I need to stop eating.",
        "No more!",
        "I'm gonna be sick at this rate.",
        "That's enough food.",
        "I'm gonna be sick...",
        "I think I'm gonna throw up...",
        "I'm full!",
    },
    hungry = {
        "Could do with a bite to eat.",
        "I'm hungry.",
        "I feel hungry.",
        "I want to eat!",
        "I feel peckish.",
        "Stomach's buggin' me.",
        "My tummy's all rumbly.",
        "Could have a snack...",
        "I need a snack.",
        "Getting hungry.",
        "Snack time.",
        "Lunchtime.",
        "I need food.",
        "I'd love some food.",
        "My stomach's empty.",
        "I'm hungry!",
        "Hungry.",
        "I'd devour some dinner right about now.",
        "Food?",
        "Anything to eat?",
        "Any food? I'm hungry.",
        "I want food.",
    },
    starving = {
        "I'm starving.",
        "I really want to eat.",
        "So hungry...",
        "I'm REALLY hungry.",
        "I need to eat... Please.",
        "I feel malnourished.",
        "I'm gonna bite my arm off.",
        "Really hungry.",
        "I'm starving!",
        "Starving...",
        "I'm so hungry... I could eat a... uhh... a... uhm...?",
        "I'm starving for a bite to eat.",
        "I'd kill to eat something.",
        "I feel so weak... I'm hungry...",
        "I'm SO hungry!",
        "I'm really starving here.",
        "I'm malnourished.",
        "I'd eat anything right now!",
        "I'm gonna starve...",
        "My stomach's hurting for food...",
        "Uggh... Hunger pains...",
        "Ghh... stomach... hungry.",
        "need.. food...",
        "Food...",
        "Uuuugh. I really want a bite to eat.",
        "My stomach's really empty.",
        "Ghh... I'm STARVING!",
        "My body is wasting away...",
    },
    thirsty = {
        "I'm thirsty.",
        "I'd love a drink.",
        "I feel thirsty.",
        "I'm thirsty!",
        "Thirsty.",
        "Need water.",
        "I need water.",
        "I want a drink.",
        "My mouth's dry.",
        "Water would hit the spot.",
        "Mouth's a little dry.",
        "Bah... thirsty...",
        "I need a drink.",
        "Never enough water.",
        "Any water?",
        "Water?",
        "Could do with a drink.",
        "I'd love to quench my thirst.",
        "Could do with some water.",
    },
    dehydrated = {
        "I'm really dehydrated.",
        "I'm really thirsty...",
        "I'm parched!",
        "I'm going to dry out.",
        "I REALLY want a drink!",
        "I need water... anything...",
        "I'm so thirsty...",
        "I might die of thirst...",
        "I'm going to... waste away...",
        "I need to find... water... fast...",
        "I need water... Now.",
        "I'm getting dizzy... I need water...",
        "Im seriously dehydrated.",
        "I've been without water too long.",
        "Water... fast...",
        "Need... water...",
        "Water...",
        "No water...",
        "Water? Please...",
        "I'm so dehydrated...",
        "I feel like I'm going to shrivel up and die...",
    },
    limbmuscle = {
        "I can't move my <limb>!",
        "My <limb> hurts...",
        "I think my <limb> is hurt.",
        "I need a check-up.",
        "I think I really messed up my <limb>.",
        "My <limb>'s so sore...",
        "My <limb>'s screwed.",
        "I messed my <limb> up bad.",
        "Is my <limb> supposed to feel like that?",
        "There's something wrong with my <limb>...",
        "Ough! My <limb> feels weird!",
        "My <limb> feels funny.",
        "My <limb> isn't working.",
    },
    limbinfected = {
        "My <limb> looks all swollen...",
        "My <limb> feels really weird.",
        "I think I caught something...",
        "Something's up with my <limb>.",
        "My <limb> feels weirdly warm.",
        "My <limb> feels... diseased.",
        "My <limb> hurts to the touch.",
        "I think my <limb> is infected!",
        "My <limb> feels really weird.",
        "There's something wrong with my <limb>...",
        "My <limb> hurts and feels weird!",
        "Ough... My <limb> feels bad.",
    },
    limbskin = {
        "My <limb> looks mangled!",
        "My <limb> is wounded...",
        "Is my <limb> supposed to look like that?",
        "I need to bandage up my <limb>!",
        "My <limb> feels exposed... I could get infected...",
        "I really tore my fur up...",
        "I need to take care of my <limb>... it looks terrible.",
        "My <limb>'s all torn up.",
        "The fur on my <limb>'s all messed up.",
        "Messed my <limb> up real bad... Ouch...",
        "My <limb>'s so sore... Ugh.",
        "My <limb> is all scratched up...",
        "I feel like my <limb> is going to get infected...",
        "My <limb> looks hurt.",
        "My <limb> looks wounded.",
        "My <limb> isn't looking well...",
        "My <limb> is all bloody...",
        "Goodness gracious! I appear to have mistaken my calculations and now my <limb> is fully yellow! Oh dear god! What do I do now!",
    },
    sad = {
        "Things could be worse.",
        "Hmm...",
        "Am I doing things right?...",
        "I must keep going.",
        "Just need to keep going...",
        "This probably isn't so bad...",
        "What else could go wrong?",
        "Uhm... hmm...",
        "Ugh. C'mon...",
        "I've been through worse...",
        "Just worse than usual...",
        "I can do this... I can do this...",
        "Just breathe in, and breathe out...",
        "I could do better...",
        "Can't give up yet...",
        "This is my life now.",
        "Just keep moving.",
        "Getting a little tired of this.",
        "Not my lucky day.",
        "I can't let all of this get to me...",
        "Things are just rough sometimes... Yeah...",
        "Ugh.",
        "I feel down.",
        "I don't like what's happening.",
        "W-why am I even here?",
        "Why me?",
        "It's lonely in here.",
        "I miss any sort of companionship.",
        "I wish I had someone alongside me.",
        "I feel lonely.",
        "I wish I could find a friend...",
        "I wish there was someone...",
        "I'm starting to feel the isolation.",
        "I'm scared.",
        "Is this what my life is going to be now?",
    },
    gloomy = {
        "Things could be better.",
        "This is just... terrible.",
        "I hope things get better. Quick.",
        "This is going down hill...",
        "I'm getting tired of this.",
        "Ugh... this sucks...",
        "I'm not content with this.",
        "This can't get any worse.",
        "My patience is being tested...",
        "What's gonna happen now?...",
        "Can't give up yet...",
        "I have no luck at this point.",
        "I don't like where this is going.",
        "I hate this. Ugh.",
        "Feeling a bit under the weather.",
        "Recent events have been terrible.",
        "I wouldn't mind something fun right now.",
        "I need entertainment or something... ugh...",
        "Absolutely tired of this.",
        "Terrible. just... terrible...",
        "From one thing to another...",
        "Things better straighten up...",
        "Fuck this... Ugh!",
        "Morale's low.",
        "Ugh!",
        "I'm in the dumps.",
        "I feel really down.",
        "Man...",
        "It's REALLY lonely in here...",
        "Uugh... I could really use... Anyone, right now.",
        "It's SO lonely here...",
        "I wish there was another living soul with me...",
        "Lonely... Really lonely...",
        "I need some support...",
        "Alone.",
        "I'm really scared...",
        "Fuck this, man... Ugh...",
        "I really want out of here.",
        "I'm unhappy.",
    },
    depressed = {
        "I can't take this anymore.",
        "...Why am I trying this?",
        "I should... just... let go...",
        "I can't keep going on like this...",
        "Should I... keep trying?",
        "There's no point to this...",
        "Please... anything to make me feel better...",
        "Can something ease my suffering? Anything?",
        "I just want this to stop.",
        "This is my life now... Great.",
        "I'm too pathetic for this...",
        "This place is going to tear me apart.",
        "I'm not going to make it through this.",
        "What am I going to do...",
        "I'll never get out of this.",
        "Fuck this.",
        "What's even the point anymore.",
        "I can't do this... much longer.",
        "I need something to help me forget this.",
        "I feel. Terrible.",
        "Why did they do this to me?",
        "Who dumped me here, just for me to suffer?...",
        "I wish I could just... understand this more.",
        "I need to distract myself.",
        "...Not....Okay....",
        "I feel genuinely horrible.",
        "DAMN it!",
        "I want to cry...",
        "Maaaannnnn...",
        "I could just lay down and die on the spot.",
        "I'm struggling really bad...",
        "It's... SO lonely in here...",
        "I'm going to fucking kill whoever is putting me through this.",
        "I am going to fucking snap.",
        "I want to smash my head against the wall.",
        "I'm going to claw my fucking eyes out.",
        "I'm starting to want to hurt myself.",
        "Oh... Oh no.",
        "...",
        "Damn it... DAMN IT!!! Why the FUCK am I HERE???",
        "I pray my death will be swift when it comes.",
        "I'm genuinely starting to consider ending my life.",
        "Don't push me any fucking further.",
        "I don't... I don't want to die here...",
        "Someone... Anyone... Please, help me...",
        "HEEELPPP!!! ANYONE!? PLEASE!!!...",
        "There's no point to this, is there?",
        "All of this is fucking revolting.",
        "Life hates me.",
        "AAAHHH!!",
        "Hahahaha...",
    },
    miserable = {
        "I want to end my life.",
        "I'll do it. I'll do it. I swear.",
        "...Why am I trying this?",
        "End my life.",
        "Kill me. Kill me. Kill me. Please kill me.",
        "I wish not to wake up.",
        "I can't do this. I just can't.",
        "Was I born, to only feel pain?",
        "They won't get away with this.",
        "Make it stop... Make it stop...",
        "I'm. this close.",
        "I need to be high. I need it.",
        "I'm going to end my fucking life.",
        "I am about to FUCKING snap.",
        "I'm not getting this god damned battery if my life depends on it.",
        "I'd rather kill myself than walk another 2 steps.",
        "I'm completely hollow.",
        "This is not worth living through.",
        "I will claw my fucking arteries right out of my damned wrist.",
        "STOP. THIS.",
        "I DON'T WANT TO FUCKING CONTINUE THIS.",
        "I WILL rip out my fucking jugular at this rate.",
        "One more fuckup and I swear I'm going to slit my wrists.",
        "I am so fucking done with all of this.",
        "I'm not willing to walk another step.",
        "I WILL turn myself into a yellow fucking paste.",
        "I'm going to DEVOUR whoever put me here.",
        "Is this a fucking joke?",
        "I'm going to fucking cannibalize myself.",
        "I. Am. Going. To. FUCKING. SNAP.",
        "WHY!?",
        "AAAHHHHHHH!",
        "HEELPPP!!! PLEASE!",
        "THIS IS TOO FUCKING MUCH.",
        "Ahahahah...",
        "Hmph.",
        "Ain't this just fucking lovely?",
        "Mhm.",
        "Okay.",
        "I'm going to end my life.",
        "...",
        "FUCK. This.",
        "W-what's happening again?",
        "Hahaha...",
        "Ooohhh boy...",
        "It'll all be over soon. I swear.",
        "I died the moment I arrived here.",
    },
    selfharm = {
        "Hahahaha... FUCK yeah... That's good...",
        "Thaaatttt's better... Ahahaha... Fucking amazing...",
        "Oh yeah... Fuck yeah... FUCK yeah...",
        "Mmhh... Fuck... Hahahaha... This is good...",
        "How do yoouuuu like that... Fucker... Ahaha... FUCK you... Fuck you... Good...",
        "Fuck me, hahah... That feels amazing...",
        "AAGH! FUCK YEAH! Fucking amazing...",
        "FUCK! HAHAHAHA! HELL FUCKING YEAH..!",
        "Just a little cut... More... Ahahah... Fuck...",
        "Ouch-... T-that's good... Fuck... That's great...",
        "FUCK! Hahaha! FUCK yeah! Hahahaha...",
        "That's what... you get... Dickhead... Fuck you... Hahahaha...",
        "There... we go... hahah... good...",
        "That'll.. fuck... Yeaaahhh... That'll do it... Haha...",
        "Y-Yeah... take that... Fucker... That'll hurt good...",
        "You deserve this... Haha... That hurts greeatt...",
        "AAHHAHA!! FUCK yeah... Fuck yeah. Hahaha... Hurts...",
        "Hahah... that's better... yeah... Much better...",
        "Theeeree we go... That hurts gooooood...",
        "Hehhehheh... that fucking hurts... hurts good...",
        "That... hahah... hurts good... Great...",
        "Let's not end this juuuussst yet... F-fuck... That's good...",
        "I don't need that flesh... Ggrhh... Haha... More of this...",
        "F-fuck... Ahahaha... Feels great...",
        "Goooooodd.... Mmmh... Finally... Finally... Fucking amazing... Mmmhh...",
        "M-maybe... Maybe I'll end it next time... Hahaha...",
    },
    angeronitem = {
        "UGH! FUCK this thing! Grhh...",
    },
    suicide = {
        "Goodbye. Good FUCKING BYE. I am DONE!!! FUCK ALL OF THIS!",
        "I'm done. Fuck this, fuck me and FUCK you.",
        "I fucking told you. I TOLD you, you piece of shit. I'm DONE!",
        "I'm leaving this shitty world once and for all.",
        "Peace. Bye. Fuck this. I'm fucking leaving. I'm going to hell for this.",
        "I have FUCKING had it with all of this. I am DONE! FUCK OFF!!!",
        "End of the line, fucker. End of the fucking line. I'M OUT!!!",
        "That should do it... Bye-bye... Sorry for this... I hope there's an afterlife for me...",
        "This is the end. I hope whoever finds my corpse makes good use of me. I can't handle this anymore. I'm sorry.",
        "There's no point to this anymore. There NEVER fucking was. I'm ending it all. Fuck me... Fuck ALL of this.",
        "If slitting my wrists doesn't kill me, I'm going to gouge my own fucking eyes out, so I never have to see this horrible land ever again.",
        "I don't know what comes after, but I can finally rest... Let's relax now... There is no need for emotions anymore...",
        "AHHHH! FUCK THIS! ALL OF THIS! I CAN'T TAKE IT ANYMORE! LET ME OUT OF HERE! I'M DONE!",
        "That's it. I've FUCKING had it. I'm finally doing this... Peace. Fucking PEACE. I'm OUT.",
        "I have made the conscious decision to end my life, right here and right now. Farewell, dipshits.",
        "I told you... I TOLD YOU. Piece of shit... Fuck... Burn in the fucking depths of hell.",
        "I'll do better as a rotting corpse. My life ended the moment I was sent here. Goodbye.",
        "This is for fucking EVERYTHING! I'M DONE! AAAHHHH! FUCK ALL OF THIS!",
        "I'm. I'm just... I'm done. No time for suicide notes. I'm so tired of all of this. Goodbye.",
        "N... no hard feelings... right?.. hah... I'm... I'm so tired... G-goodnight...",
        "I'm not doing this anymore. I'm not. It's over. Bye. Ello. Fuck this.",
        "There never was any hope. FUCK. This. I'm OUT! LEAVE ME ALONE! I'M NOT LETTING THIS PLACE TAKE MY LIFE!",
        "Looooook at that... Hahahah... I'm saying goodbye to this fucking universe... Leaving this world behind... It's... Relieving...",
        "There... There it goes... Let's enjoy my last few moments now... Relax and... Fall asleep... One last time...",
        "I hope you're happy with what you've done. Dipshit. Fuck you. FUCK YOU. Go to hell.",
        "There goes my wrist... It's all going to be over soon... Haha...",
        "Fuck you. FUCK you. I'm DONE. I'M FUCKING DONE!",
        "I am LEAVING this fucking place, whether I'm able to or NOT. FUCK YOU.",
        "FUCK this. It's fucking OVER. To hell with my life.",
        "To hell with this. I'm out. Piece of shit. I'm done. I'm done. I'm done. I'm done. I'm done. I'm done. I'm done.",
        "Piece of shit... I'm fucking done... Fuck this...",
        "I'm leaving. I hope I'm not going to hell for this.",
        "They can find me as a desiccated corpse in a ditch. Like it fucking matters.",
        "None of this matters. This is a suicide mission. I'm not fucking going through any more of this.",
        "I've failed. I give up. Fuck this.",
        "Good fucking luck to anyone that comes here after me. Maybe my corpse will be of use to someone. I'm done.",
        "There never was any fucking point to this. I was sent here to die.",
        "They're getting what they fucking wanted.",
        "I didn't think I was ever actually going to do this... Haha... Ahahahaha... Cathartic...",
        "I'm taking my life. Sorry. I can't. I fucking can't take it anymore. I'm so fucking sorry.",
        "I hope I end up in hell. Gonna be better than this fucking place. I can't. I'm out. Sorry. Fuck all of this.",
        "Bye. I'm out. I'll see everyone on the other side, down in the pits of hell.",
        "Fuck this. Fuck this. FUCK. This. I'M DONE! ENOUGH OF THIS.",
        "Sorry. I'm out. Bye. I'm sorry. I'm so fucking sorry. I can't.",
    },
    refuse = {
        "...",
        "...No.",
        "Do I have to...?",
        "...",
        "Nh...",
        "Uugh.",
        "Nnh...",
        "No.",
        "I... can't.",
        "...nnh...",
        "...",
        "...but...",
        "Eh...",
        "...eh",
        "Why...",
        "Really?...",
        "...",
        "...",
        "W-w-wait...",
        "Hn...",
        "Fuck you.",
        "Hell no.",
        "...",
        "But why.",
        "Why should I.",
        "...",
        "I...",
        "B-but...",
        "Nuh.",
        "...",
        "H-hold on...",
        "...",
        "...?",
        "But...",
        ".....",
        "Meh...",
        "...",
    },
    bleeding = {
        "I'm bleeding!",
        "Help! I'm bleeding!",
        "I'm losing blood!",
        "I'm spilling blood all over the place!",
        "I'm wounded!",
        "I need to patch myself up!",
        "Bleeding!",
        "This isn't great...",
        "Losing blood...",
        "I'm losin' my life juice!",
        "I'm bleeding.",
        "I'm bleeding! Help!",
        "Need a bandage!",
        "I don't like bleeding...",
        "I'm oozing blood...",
        "My blood... ",
        "That's my blood...",
        "Oh... that's blood...",
        "I need a patch-up.",
        "Oh! Blood! Shoot!",
        "Uh... blood? Not good...",
        "My blood, no!",
        "I need this bandaged. Fast...",
        "Crap, I'm bleeding!",
        "Bleeding...",
        "That's my blood... ouch...",
    },
    bleedingheavy = {
        "There's so much blood...",
        "Fuck... I'm dying...",
        "Agghh...",
        "Help me! ...Please...",
        "Fuck, fuck, fuck... This is bad...",
        "Help me... Please...",
        "Shit. Oh no. Oh GOD.",
        "No no no no no. Oh my god...",
        "I don't want it to end like this... Help me...",
        "This requires urgent attention...",
        "HELP ME! PLEASE!",
        "I am bleeding the FUCK out...",
        "I-I'm not ready for t-this...",
        "This is bad. This is bad. This is BAD.",
        "Ain't this going... A-amazing...",
        "This is h-horrifying...",
        "Why... Why is... I... Need help...",
        "FUCK! FUCK! BANDAGE!",
        "HELP ME! I'M... Bleeding... Please...",
        "Are... Are these my last moments..?",
        "Focus... Focus... We can fix this...",
        "I can fix this... Come on... Fuck...",
        "This is a... fucking... nightmare...",
        "AHHHH! AAAAAHHHH!",
        "No, no no. No. Please. Fuck. FUCK. H-help me...",
        "*terrified*",
        "I-I-I... Oh... N-No... I... Oh g-god...",
        "I-is this it...",
        "F-fuck... Focus... I can s-salvage this...",
        "Oh god. Shit. I... I'm scared...",
        "My vision is all blurry...",
        "Bandage! U-urgent...",
    },
    steponglass = {
        "Let's clear up the glass shards next time...",
        "I think that was glass I stepped on...",
        "There's a big glass shard in my paw.",
        "Can we please avoid stepping on broken glass?",
        "That was horribly careless of me.",
        "I need to clean up any broken glass I procure.",
        "Let's NOT step into glass shards.",
        "I'd prefer to avoid inserting glass into my feet.",
        "Those windows clearly weren't tempered.",
    },
    seecorpse = {
        "Oh... Oh god.",
        "Shit.",
        "Better you than me, buddy...",
        "That's not very reassuring.",
        "Hey! Are you... O-oh...",
        "Fuck me man... That's a bad sight.",
        "No no no no. Oh god...",
        "I feel bad for them...",
        "I hope I won't end up like this.",
        "Yikes... Ew... Man.",
        "I don't think they're breathing...",
        "Yep, that's a corpse alright...",
        "I can't help but stare...",
        "Fuck that... Ough... That sucks.",
        "Poor little guy.",
        "Fuck...",
        "Awww... That's a sad sight.",
        "I knew there were more of us here...",
        "It's gonna be okay... It's gonna be okay.",
        "Oh fuck. They're dead...",
        "*gasp*",
        "*frown*",
        "Someone should give them a proper burial.",
        "I shouldn't touch them...",
        "God fucking damn it. Ugh. They're dead.",
        "I thought I found someone for a second... Fuck...",
        "How many of us have died here...? God... That's not a nice sight.",
        "I better not end up like this.",
        "...",
        "...!",
        "Oh damn it. Fuck. I hate that...",
        "I wish I could've given this guy a hug before they passed away.",
        "God...",
        "I want to leave this place... Fuck...",
        "That's a dead guy...",
        "I hope it wasn't painful, at least...",
        "Awww... Poor thing...",
        "I'm scared I'll meet the same fate...",
        "AHH! That's a corpse! Fuck...",
        "Oh fuck... That's one of our own... Ooohhh no...",
        "Well, that's demotivating.",
        "They're... They're not breathing...",
    },
    seecorpsedesensitized = {
        "And another...",
        "There really are a lot of us down here.",
        "Mhm.",
        "Anythin useful on ya, buddy?",
        "There's so many...",
        "I think I'm getting used to the sight.",
        "I think this counts as genocide at this point...",
        "So many innocent lives lost...",
        "This one looks funny.",
        "I've seen a lot of these by now.",
        "This place is FILLED with corpses!",
        "I wonder if I'll find someone living in here...",
        "That's gotta hurt.",
        "Not a good mortality rate in here.",
        "This place has taken so many lives...",
        "I'm better than this...",
        "That looks like it hurt.",
        "This one is still smiling!",
        "I already lost count.",
        "Someone ought to arrange a funeral for 'em...",
        "That sucks...",
        "Every time I see one of us like this, a little piece of my soul breaks off.",
        "Free shit!",
        "Haha... Finders keepers...?",
        "I wonder if any of them can be saved.",
        "Hahaha...",
        "Hey! You! ...Yeah, they're not any different.",
        "Man, these guys must REALLY not like me... Not a single one even looked at me!",
        "Let's just move on.",
        "Survival of the fittest, I guess...",
        "Eugh.",
        "And another one.",
        "And another!",
        "Aaaannnd another one...",
        "...Yep, that is another corpse!",
        "More corpses...",
        "I thought I recognized that one for a second...",
        "So many dead guys...",
        "This is getting boring by now.",
        "I'm astonished how many of us have died here.",
        "....",
        "It's that time of the day again...",
        "I have a sneaking suspicion this one is dead.",
        "Fuck.",
        "What do we have here...",
        "What'chu got...",
        "Hey, little dead fella.",
        "I don't think this guy will need their stuff anymore.",
        "...More for me! Haha.",
        "This one looks funny. Haha!",
        "This one looks silly...",
        "They're smiling at me!",
        "Hey.",
        "Hello there!",
        "Such generosity.",
        "I'd be grave robbing if this guy had a funeral.",
        "...And. That, ladies and gentlemen... Is another corpse.",
        "Ooh.",
        "Friend! Nooo... No friend...",
        "That's not sanitary.",
        "I don't think they enjoyed their stay.",
        "Ough, you smell! Go take a shower...",
        "Mmh...",
        "Aaaanother...",
        "Seeing all of these is saddening.",
        "I'd make a joke, but I don't like disrespecting the dead.",
        "Yeah...",
        "Someone got unlucky.",
    },
    seecorpsesuicidal = {
        "I'll join you soon.",
        "Not long until I end up like that.",
        "I wish I was in their place.",
        "Everything will end soon.",
        "Maybe I wont be so miserable on the other side.",
        "God, I want to be fucking dead too...",
        "Being a corpse sounds very attractive right about now.",
        "At least you managed to escape...",
        "You've found your escape.",
        "I don't blame you.",
        "Any room for me...?",
        "Yeah, fuck this place, buddy. I'll be with you soon enough.",
        "I fucking hate this world.",
        "I'll end up like this soon enough.",
        "This brings me comfort. A reminder that it'll all end soon.",
        "You got lucky.",
        "I wish I was as lucky as you are.",
        "I agree.",
        "Yeah. This is a burden not worth carrying.",
        "I can't wait for when I get the guts to end it.",
        "I'm jealous.",
    },
    breakcorpse = {
        "Why did I do that... Ew...",
        "That's disgusting... I don't want to do that again.",
        "Ew!!!",
        "Demoralizing.",
        "This fucking sucks.",
        "I'd prefer not goring random corpses I find...",
        "Fuck that. Ugh.",
        "Disgusting!!! Agh...",
        "Let's not do that again...",
        "There's blood all over me... Ew...",
        "That was one of our own...",
        "Did I HAVE to do that..? Y-yuck...",
    },
    cold = {
        "It's cold in here.",
        "It's chilly!",
        "I feel cold.",
        "It's chilly in here.",
        "Just a hint... cold here.",
        "I'm starting to shiver.",
        "Hmph... cold.",
        "Is it me or is it cold?",
        "Feeling a little cold.",
        "Cold in here...",
        "I should try to stay warm.",
        "Brrr.",
        "I feel a little chilly.",
        "It's nippy in here!",
        "I'm cold.",
    },
    warm = {
        "It's a little hot in here.",
        "I feel warm.",
        "I'm a little too warm.",
        "Too warm for comfort.",
        "I'd like to cool down.",
        "I'm starting to sweat a bunch.",
        "I need to cool off.",
        "I'm uncomfortably hot.",
        "I need to chill out- literally.",
        "Something to cool me off would be nice...",
        "I'm burning up...",
        "It's a little warm here...",
        "I'm sweating!",
    },
    hot = {
        "I feel hyperthermic...",
        "Huff... Puff... Hot...",
        "It's so hot...",
        "I feel hot...",
        "Too hot...",
        "I'm gonna melt...",
        "I'm gonna pass out...",
        "I feel like im smoldering.",
        "My head's dizzy... It's too hot!",
        "I can't think straight with this heat.",
        "I feel sick from this heat...",
        "I'm tired of burning up.",
        "Something to cool me off would be great!",
        "I'm gonna cook at this rate...",
        "I'm boiling in this heat... ugh.",
        "Whew, it's hot!",
        "Hot...",
        "Need to cool down...",
    },
    exerted = {
        "Huff... Puff...",
        "I'd like to stop for a moment.",
        "What an exercise!",
        "Can we pause...",
        "I need a pause...",
        "Whew... i'm exhausted...",
        "I'm a bit drained...",
        "I need a break.",
        "I should stop a bit... I feel all flimsy.",
        "I need to take a moment...",
        "I need a moment to sit.",
        "I'm a little exerted...",
        "Gosh... so much work...",
        "I'm worn out...",
        "Taking a break sounds good...",
        "I feel exerted...",
        "Real workout over here!",
        "I want to rest!",
        "Let's sit down for a moment.",
    },
    exhausted = {
        "I'm exhausted...",
        "Huff... Huff... Puff...",
        "Ouugh... Exhausted...",
        "I need to sit down...",
        "I'm... so tired...",
        "Wait for a moment...",
        "My muscles hurt...",
        "I can't move...",
        "I can barely stand...",
        "I'm gonna collapse at this rate...",
        "My lungs... uugh...",
        "My chest hurts... whew...",
        "Gosh... I'm worn out...",
        "Just... need a minute...",
        "Gotta... take a break...",
        "I need a break...",
        "Running on... empty...",
        "I'm out of juice...",
        "Out of... energy...",
        "Feeling drained...",
        "Could... sit down a bit...",
        "Can't catch a breath...",
    },
    freezing = {
        "I'm freezing...",
        "It's so cold...",
        "I need... warmth...",
        "I'm gonna freeze...",
        "The cold... hurts...",
        "I'm shivering so bad...",
        "Im getting all numb...",
        "Too... cold...",
        "Brrr...",
        "Brrrrrh...",
        "Shivering... tch...",
        "I need warmth... bad...",
        "I'm going to freeze to death...",
        "I'm too cold... way too cold...",
        "I'm too cold...",
        "So so cold...",
        "I need to get warm- now...",
        "Anything... to warm me up... please...",
        "I need to get to somewhere warm.",
        "Cold...",
        "So cold...",
        "I'm freezing!",
        "Freezing...",
    },
    emaciated = {
        "I am so thin... I feel weak.",
        "I REALLY need to pack on a few kilos.",
        "I'm very out of shape.",
        "This kind of weight loss might end very badly for me at this point.",
        "I really need to eat more...",
        "I'm way too skinny... This can't be good for me.",
        "My figure is so lean...",
        "I'm like a low calorie diet drink.",
    },
    obese = {
        "I sure gained some weight.",
        "I feel so heavy and sluggish.",
        "I'm really fat.",
        "...Am I not a bit overweight?",
        "I need to drop a few kilos.",
        "I can see the fat building up on me...",
        "I can't continue eating this much.",
    },
    opiated = {
        "I think I'm drugged...",
        "I feel woooooozzzyyy...",
        "It's hard to focus...",
        "This feels gggreeatttt...",
        "This can't be good for me but I feel great.",
        "Ha-ha... I like this...",
        "What did I just put into my body...",
        "I feel... Sleepy...?",
        "I... Can't focus...",
        "I feel like something's in my lungs...",
        "It's a bit hard to breathe...",
        "I feel like I'm gonna pass out... And I love it...",
        "I feel funny...",
        "Ooggh... yeaaaahhh...",
        "I'm tingling...",
        "I love this... feeling?...",
        "I want more of this...",
        "I want more of whatever this is...",
    },
    opiatedsad = {
        "That's... much better.",
        "I can... relax now...",
        "Finally... a sense of peace...",
        "I really... needed that...",
        "I just need to relax... I just need to relax...",
        "This'll calm me down... this'll... oogh...",
        "I really need this.",
        "I feel at... ease...",
        "Distract me...",
        "I feel so much... better...",
        "That'll shut... me up...",
        "I feel better... Ohh... yes...",
        "Enough thinking...",
        "I could... do this more!...",
        "Freeeedooooommm...",
        "Thank you, silly stuff...",
        "I need to stop thinking... stop thinking...",
        "Just to... Get my mind off of these things...",
        "Clear my mind... clear my mind...",
        "No more... suffering...",
        "Ahhhhhh... good...",
    },
    opiatewithdrawal = {
        "I... I need drugs...",
        "Opiates... Please...",
        "I-I really n-need more opiates...",
        "I'm all shaky...",
        "I could chug an entire b-bottle of painkillers...",
        "I think I'm going t-through withdrawal...",
        "I-I really n-need another shot...",
        "F-fuck... I feel terrible... I really need... something...",
        "I'm... I'm so shaky... I need some more...",
        "I feel terrible- I need... I need more of that stuff...",
        "It's getting to me... I'm shaky... Fuck.",
        "Need... more... opioids.",
        "I'm f-feeling so... terrible... I-I need more...",
        "Painkillers...",
        "I... I need something... I need that high...",
        "F-Fuck... uuggh... withdrawal...",
        "I'm- f-feeling like shit... I need a dose- NOW.",
        "I-I could use a dose right about now.",
        "I could u-use a dose.",
        "I'm... getting the shakes...",
        "I need to stop using this crap...",
        "All I can think a-about is another shot...",
        "Opioids...",
        "I'm so shaky and lightheaded... I-I need more opioids...",
        "Need more... D-drugs...",
    },
    cantBreathe = {
        "I can't breathe!",
        "I... can't breathe...",
        "Help... I'm suffocating...",
        "Cough! Cough! Ack!",
        "I'm passing out...",
        "What's happening... Help...",
        "Cough- H-help...",
        "I c-can't breathe...!",
        "I'm-... Suffocating!...",
        "Ahk! Cough!",
        "Need... Air!...",
        "M-My... neck!...",
        "I can't.... Cough! Hack!",
        "Help- Ack! Cough!",
        "H-help...",
        "My... chest...",
        "My... chest- Cough! Hack!",
        "My lungs...",
        "*gasping*",
        "I feel like I'm dying...",
        "I'm gonna... pass out...",
        "Can't... breathe...",
        "My insides...",
    },
    pain = {
        "Ow!",
        "Ouch!",
        "Oww...",
        "Ouchhh...",
        "This hurts...",
        "This hurts!",
        "Agh!",
        "YELP!",
        "Ough!",
        "Ack!",
        "This... hurts!",
        "My <limb>... Ouch...",
        "Ow! Ugh...",
        "Fffhhh... hurts...",
        "That- hurts!",
        "Ack! Ow!",
        "Ghn!",
        "Ouchy!",
        "I'm in pain...",
        "Owww!",
        "Ow...",
        "I ache...",
        "My <limb> hurts...",
        "Ouch! My <limb>!",
        "My <limb>!!",
        "My <limb>'s hurting...",
        "My <limb>'s... screwed...",
        "Ack! My <limb>!",
        "My <limb> hurts!",
        "Oww... My <limb>...",
        "My <limb>'s in a lot of pain...",
        "Ouch... My <limb>!",
        "Gah! Damn it! My <limb>!",
        "Damn... My <limb>!",
        "My <limb>...",
        "My <limb>'s aching...",
        "This hurts... Ouch... My <limb>!",
        "There's something really wrong with my <limb>.",
        "I need something to ease the pain...",
        "Let's take it easy for a while... My <limb> hurts real bad.",
        "Fuck- Wait... My <limb>... Awh...",
        "My <limb> is so sore...",
    },
    hitgroundhard = {
        "Agh!",
        "Gack!",
        "Fuck!",
        "Augh!",
        "Ghagh!",
        "Ugh!",
        "Ngghh!",
        "Ow!",
        "Gggouch!",
        "Argh!",
        "Nffgh...",
        "Aaawgh!",
        "Ngghhh...",
        "Ough!",
    },
    bigpain = {
        "OW!!!",
        "AGH!!!",
        "AUUGHH!",
        "AUUGHNN!",
        "OOAUAUGHHH!",
        "NHHGHH!",
        "FUUUCK!",
        "OOOWHHG!",
        "NHHGFFF!",
        "GAAH!",
        "HELP! AAHG!",
        "OWW!!!!",
        "OOUUUUCH!",
        "GGHHHBN...",
        "HEELPPP!",
        "AAAH!",
        "FUCK!",
        "CRAP!!!",
        "AHHH!!!",
        "HELP!!!",
        "NGHH!",
        "AGH...",
        "PLEASE!!",
        "STOP!!!",
        "DAMN IT!!!",
    },
    fallscream = {
        "AAAAH!!",
        "AAAAHHH!",
        "CRAAAP!",
        "AAAAAAAA!",
        "AAGHHAH!",
        "SHIT!",
        "WAAAAHHH!",
        "WOOAAAH!",
        "WAAAAHH!",
        "OOOOOHHH!",
        "WHEEEAAAA!",
        "OHH! AHHH!",
        "OHHHHSSHHH!",
        "FUUHHH!?",
        "WHHAAAA?!",
        "HEEEEEY!",
        "AAHHHHJG!",
        "AAAAACK!",
        "AAH!",
        "AAAAAAAAAAHHH!",
    },
    hitbycreature = {
        "AAAHHHHH!",
        "AAAAAAAAHHHHH!",
        "AHHH!! FUCK!!!",
        "GAAAHHHHHH!!! GET IT OFF!",
        "GET IT OFF OF ME! AAHHHH!",
        "GET AWAY!",
        "AAAAAAAAAAAAAA!",
        "STOP!!! AAHHHHHH!",
        "HELP ME! HEEELPPP!",
        "AAHHHH FUCK! FUCK! GET AWAY FROM ME!",
        "AAAAHHHHHHH!",
        "*gasp*",
        "SHIT! FUCK! FUCK! AAHHHHHH!",
        "NOOOOO! AHHHHHHHHH!",
        "AAGHHHHHHHH! FUCK! FUCK!",
        "FUUUUCKKK! GET AWAYY!!! AAAAHHHHHH!",
        "NNGAHHHHH!! AAAAAAHHHHHH!",
        "AAAAAAAHHHHH!! FUUUUUCK!!",
        "NNNONONO-AAAAAAAHHHHHH!",
        "!!!!!!!!",
        "AAAAAAAHHHH!!!!!",
    },
    wet = {
        "I'm drenched...",
        "I'm soaked!",
        "I'm completely drenched.",
        "Eugh! There's water on my fur...",
        "I'm so wet... Ugh...",
        "I'm covered in water!",
        "I am MOIST.",
        "I'm uncomfortably wet...",
        "I'm dripping wet.",
        "I hate this wet feeling.",
        "Let's not get drenched next time...",
        "My fur's all wet and sticky...",
        "Very damp in here.",
        "Way too moist in here!",
        "Get this water off of my skin.",
    },
    dirty = {
        "Ugh... I'm so dirty!",
        "I really need a bath.",
        "I'm covered in bog.",
        "I'm all covered in dirt.",
        "Eugh... My fur is all dirty.",
        "I think I need a shower.",
        "It might just be me, but I think I'm starting to smell.",
        "All this dirt on me... I feel like an animal.",
        "This is not very hygienic...",
        "Can't I take a quick bath?",
        "I should clean myself.",
        "I need to clean off all this dirt.",
        "Way too dirty.",
        "Really should wash all the dirt off...",
        "Let's not get THIS unclean...",
        "Time for a bath!",
        "I'm pretty sure those lifepods have showers in them... I really could use one.",
        "How'd I get so dirty?",
        "Gosh, I am COVERED in gunk!",
        "My fur is so yucky!",
        "Guh! I'm completely covered in filth.",
        "There's soot in my fur.",
        "I feel filthy. I really need a bath, or something...",
        "Could do with a shower!",
    },
    encumbered = {
        "Carrying a bit much.",
        "Do I need this much on me..?",
        "I'm kind of weighed down...",
        "I should drop some things...",
        "I should leave some of my belongings, they're really heavy...",
        "Ough, I'm way too weighed down.",
        "Carrying too much...",
        "I'm hoarding too much...",
        "As much as I feel like all of these things will be useful, I'm really weighed down...",
        "The load is a little much...",
        "I feel weighed down by all I am carrying.",
        "Let's lighten the load a little.",
        "I'm a bit overloaded with gear.",
        "Carrying uncomfortably much...",
        "I'd love to lessen the load a little...",
        "I need to leave some stuff behind, there's too much on me.",
        "I really should free up a hand or two. I'm carrying a lot...",
        "Ugh! Too much gear on me. I feel weighed down.",
        "Hoarding a little too much... All this gear is heavy.",
    },
    watchlike = {
        "I like this watch-thing. It's comfy.",
    },
    drillend = {
        "...That took a while.",
        "I swear that thing had no soundproofing.",
        "Pretty long ride there...",
    },
    loud = {
        "FUCK! That was loud...",
        "GAH! Crap! My ears!",
        "AHHH! Fuck... My ears are ringing...",
        "CRAP! ... Ouuchhh... That was so loud...",
        "NO!!! Fuck me, man... Aghhh, that was loud...",
    },
    murderregret = {
        "Why... Why did I do that..? F-fuck...",
        "Gh... God... Why..?",
        "I... That was horrible.. I'm a monster...",
        "Nhh... Why... Why? That was one of us...",
    },
    tradeemeet = {
        "Hey!",
        "Hello?",
        "Oh! Hello!",
        "Hm?",
        "Finally, someone...",
        "...Hello?",
        "Hay!",
        "Hello!",
    },
    tradermeetnormal = {
        "Hey!",
        "Hello!",
        "Oh! Someone finally came over...",
        "Oh! Heya.",
        "Hey! Glad to see someone alive.",
        "Hey, buddy.",
        "Welcome!",
    },
    tradermeetgood = {
        "Ah! Hi!!",
        "Hello! How are ya?",
        "Aah! Hello!! Hi!",
    },
    tradermeetbad = {
        "Hheeyy...I dislike your presence..?",
        "H... Hello... Uhh...",
        "...Hey.",
        "...Hm. Hello.",
    },
    traderhugsuccess = {
        "Awww... Thank you.",
        "Ahhh... Thank you, buddy.",
        "Mmmh... Aww, thanks!",
        "Ah! Mmhh... Thank you...",
        "Aw! You're so nice!",
        "...Thank you, I needed that.",
    },
    traderhugfail = {
        "AHHH! Don't touch me out of nowhere...",
        "Hey! No touchy.",
        "Aghh! Hey! No touchies!",
        "I'll pass...",
        "No thanks.",
        "Wh- Hey! Get your paws off of me.",
        "Hey! Don't touch me! I don't trust you.",
    },
    traderhagglesuccess = {
        "...Okay!",
        "Mmmmhmmm... Got it.",
        "I'll think about it.",
        "I'll consider...",
        "Y-yeah... Sure...",
        "Makes sense to me!",
        "Uh huh.",
        "Hmm... Okay.",
    },
    traderhagglefail = {
        "You didn't sound very convincing there.",
        "...No, thanks.",
        "Nuh uh.",
        "Not interested.",
        "What? Why would I do that..?",
        "Meeehhh... Another time.",
        "Meh.",
        "...Nhh...",
        "...Ugh. Sorry.",
    },
    traderdepressed = {
        "...Uh... ...Are you okay? You look a little... Disgruntled...?",
        "...No greetings or anything...? Wh... Why are you looking at me like that...",
        "...? ...Um...  ...Hello..? ...You there..?",
        "...You look terrified. Are you okay? Hello...?",
        "Hey! How are yooouuuu......you don't look so well there, buddy... Uhm...",
        "Hey! ...What's with that piercing look? Uhm...",
    },
    tradergiveitem = {
        "Thanks!",
        "Adding that to the count.",
        "Thank you!",
        "I'll be needing that.",
        "Aye! Thanks!",
        "Good!",
    },
    tradergiveitemrefuse = {
        "Alright... That's enough for today, my bag's all full.",
        "Hey, enough gifts! I don't want to give out all my stock to you.",
    },
    traderbuy = {
        "Here you are. Cheers!",
        "Alright! Here's your pick. Good luck out there.",
        "Have this. Thank ya, mate.",
        "Here, have this.",
        "Pleasure doing business with you, haha.",
        "There.",
    },
    traderbuyfail = {
        "Gimmie a few more things.",
        "I'm not going first.",
        "Hand over a few more things first.",
        "Pay first!",
    },
    traderbuyfailmaxvalue = {
        "Sorry, that's all I'm willing to trade for now.",
        "Out of stock! Sorry! You've bought so much already...",
    },
    traderwarning = {
        "Leave.",
        "Leave. Now.",
        "Out! Get out!",
        "Leave this pod.",
        "I don't like you being here. Leave.",
        "Leave!",
        "Out.",
        "Get out of here!",
        "Get lost.",
        "Fuck off!",
        "Fuck off.",
    },
    tradercombat = {
        "I'm done with your shit.",
        "Fuck OFF!",
        "I'M DONE WITH YOU!",
        "FUCK YOU!",
        "OUT! GET OUT! NOW! OUT!",
        "GET OUT!",
    },
    traderthreatensuccess = {
        "Okay, okay, jeez... Take whatever, just don't hurt me...",
        "Asshole... Fine. Go ahead. Please leave after.",
        "Nggh... Fuck you... Take what you want and leave!",
        "Please don't hurt me! Take something and... Please leave...",
        "...Okay. Take something and do not come back. Spare the threats.",
    },
    traderlightbreak = {
        "Dude, what the fuck? Why would you do that? Fuck off.",
        "...Did you really think I would not see that. You fucker. Get out!",
        "Hey! What the hell! I needed that! Get the fuck out!",
        "Ahh! You THIEF! Get the hell out!",
        "Dude. Okay... Okay then. Okay... I... Uh... Please leave.",
    },
    traderwakegreet = {
        "Good mornin'.",
        "Hi! You're up now.",
        "Morning, sleepyhead.",
        "How didya rest?",
        "Hope you slept well.",
        "Wakey wakey!",
    },
    traderseegun = {
        "...Woah there! Put that gun away, man... Anyway.",
        "Hey! What's with the gun? Put that away, please. ...So.",
        "I hope you're not using that gun, haha.",
        "Ey, I don't have a gun, so put yours away, bud.",
    },
    tradermeetimpairedspeech = {
        "...Huh? What? Is there something in your mouth? I can't understand you...",
        "Mmmff mff mmmmfff mhfff! That's what you sound like.",
        "I get that this is a bad scenario we're in, but you can at least put in some effort into speaking clearly...",
    },
    traderseehurt = {
        "Since you're hurt, I'll let ya grab a bandage for free if you can find one around here...",
        "Aww, you're hurt. If you can find a bandage on me, you can take it! I don't remember if I have one...",
        "Ohh, you don't seem to be doing well... Tell ya what, you can grab a bandage for free if you see one.",
    },
    tradermove = {
        "Oh, sorry. Here.",
    },
    tradermovefail = {
        "Huh? Why? What are you trying to do..? I don't trust you.",
    },
    swingresponse = {
        "I'M SORRY!",
        "STOP IT!",
        "AGH!",
        "QUIT!",
        "FUCKER!",
        "Stop!",
        "AAH!",
        "NGH!",
        "FUCK.",
        "Fuck. Fuck. Fuck!",
        "YOU!",
    },
    braindamaged = {
        "I taste metal.",
        "Did I eat something metallic?",
        "I didn't know metal had a smell.",
        "There's a metal taste in my mouth...",
        "...Metal...?",
        "What     is  happening",
        "This      this  is    wrong .",
        "I'm smelling something REALLY weird...",
        "This isn't right. I feel a metallic taste...",
        "Nor something angrily nor blissfully few?",
        "An no one ourselves dry for invent by means of a most.",
        "Very Well! Dynamics two zero nine fourty-two thre two two eight two seven.",
        "Villa hastily the oho! Onto no one?",
        "Good! Certainty someone itself I urgently!",
        "For as oddly whom urgently him mate rats! Miner herself right on.",
        "Expand ptui!",
        "Travel truthfully deflation the improve which one another an a?",
        "I see shadows in my eyes...",
        "The colors of everything... It all tastes wrong...",
        "...Wh... ...What... Yeah... Yes!",
        "I smell copper.",
        "This smell does not smell possible...",
        "Si tir ti vucot svaklar si mi.",
        "The",
        "Ough! I taste metal... So much metal...",
        "Kovgam varmunch persvek sia narod!",
        "Since when does everything smell like this..?",
        "This tastes wrong. Very wrong... Am I sick..?",
        "Gh... Hh-h...",
        "What was that!?",
        "Am... Am I imagining things..?",
    },
    lastmoments = {
        "I don't... want to die... I don't want to die...",
        "Please... Please... Someone save... Save me...",
        "I don't want to die... Please... Please...",
        "Not... Not like this... Please... Help me...",
        "H-help... Someone... I don't w-want to die...",
        "I don't... I don't want to leave this world...",
        "Save me... Save me... S-save me... Please...",
        "This.. Is... H-h... Is this how... How it ends...",
        "All... Everything I've done... To... To lead up to t-this... Save m-me...",
        "No.. No.... N-no... Please... Please... I don't... I-I don't want to d-die... Help me...",
        "Ffhh... Gh.... Help me... Please... Anyone...",
        "Nhh... Not like t-this... Please... P-please... Save me...",
        "Please... I don't... I don't want to die... Save me... Anyone... Anything... I-I'm not r-ready...",
        "W-Will it be.. Over s-soon..?",
        "Stop... Stop... Stop... Please... S-stop... Not l-like this... Save me...",
        "Fuck... Fuck... Help me... I don't... Want to d-die... H-h..",
    },
    magicheal = {
        "...Huh. I feel... Better..?",
        "Ahh..! ...Huh. That feels... That feels better. I liked that.",
    },
    selfdestruct = {
        "...Uuuhh... ...What is this beeping...?",
        "...Oh. Oh. OH. OH! NO. NO NO NO. WAIT. WHY? WHAT DID I DO!?",
        "...A-ah... Alright... W-well... G-goodbye, t-then...",
    },
    vomitresponse = {
        "Uuuhmm... You good..?",
    },
    vomitbloodresponse = {
        "Ack! Did you just... Oh... Hey, you know you just... Threw up blood, right?",
    },
    hungryresponse = {
        "There's a bunch of food out there, you know...",
        "Well, I could give you food in exchange for something..?",
    },
    thirstyresponse = {
        "I'd wager you can find some water out...",
        "Last I heard you can only go for three \"days\" without water, haha...",
    },
    sadresponse = {
        "Hey, it's okay... You're still alive and kicking, right...",
    },
    depressedresponse = {
        "...Calm down, please... It'll be fine...",
    },
    selfharmresponse = {
        "...W-why... Did you...",
    },
    braindamagedresponse = {
        "...You don't sound... Very well.",
        "...What?",
    },
    hotresponse = {
        "Turn the heat down, then.",
    },
    coldresponse = {
        "You know, we do have a heater here...",
    },
    bleedingresponse = {
        "It... Does look bad... But, I... I'm sure you can fix it...",
        "H-hey, calm down. You'll be okay.",
    },
    painresponse = {
        "Are you okay..? Why do you hurt?",
        "Did you step on something?",
    },
    dirtyresponse = {
        "...We have a shower, you know. Or... Just, go swim in the pools out and about...",
    },
    encumberedresponse = {
        "Wouldn't hurt to leave some of your stuff with me.",
        "I'll take good care of your things!",
    },
    dyingresponse = {
        "Crap... Uh... I never learned how to resusciate others...",
        "I... Uh... I hope you'll be alright...",
    },
}

if WoundSystem.CAS3Locale and WoundSystem.CAS3Locale.ApplyTalkLineOverrides then
    WoundSystem.CAS3Locale.ApplyTalkLineOverrides(TALK_LINES)
end

local function IsLetter(char)
    return char and string.match(char, "%a") ~= nil
end

local function IsWhitespace(char)
    return char and string.match(char, "%s") ~= nil
end

local function RandomReplacement(pool, sourceChar)
    local repl = pool[math.random(1, #pool)]
    if sourceChar and sourceChar == string.upper(sourceChar) then
        repl = string.upper(repl)
    end

    return repl
end

local function StringChars(text)
    local chars = {}

    for i = 1, #text do
        chars[#chars + 1] = string.sub(text, i, i)
    end

    return chars
end

local function ReplaceSomeLetters(text, pool, fraction)
    local chars = StringChars(text)
    local target = math.floor(#chars * fraction)
    local tries = 0
    local changed = 0

    while changed < target and tries < #chars * 4 do
        tries = tries + 1
        local idx = math.random(1, #chars)
        if IsLetter(chars[idx]) then
            chars[idx] = RandomReplacement(pool, chars[idx])
            changed = changed + 1
        end
    end

    return table.concat(chars)
end

local function ApplyBrainDamageSpeech(text)
    local out = {}
    local chars = StringChars(text)

    for _, char in ipairs(chars) do
        out[#out + 1] = char

        if IsLetter(char) then
            if math.Rand(0, 1) < 0.12 then
                for _ = 1, math.random(1, 3) do
                    out[#out + 1] = char
                end
            end

            if math.Rand(0, 1) < 0.12 then
                out[#out + 1] = "-"
                out[#out + 1] = char
            end
        elseif IsWhitespace(char) and math.Rand(0, 1) < 0.18 then
            out[#out + 1] = "...."
        end
    end

    return table.concat(out)
end

local function ReplaceAllLetters(text, pool)
    local chars = StringChars(text)

    for i, char in ipairs(chars) do
        if IsLetter(char) then
            chars[i] = RandomReplacement(pool, char)
        end
    end

    return table.concat(chars)
end

local function IsCommandText(text)
    text = string.Trim(tostring(text or ""))
    if text == "" then return true end

    return COMMAND_PREFIXES[string.sub(text, 1, 1)] == true
end

local function GetBody(ply)
    if not WoundSystem.Health or not WoundSystem.Health.GetBody then return nil end
    return WoundSystem.Health.GetBody(ply)
end

local function GetLimbs(ply)
    if not WoundSystem.Health or not WoundSystem.Health.GetLimbs then return nil end
    return WoundSystem.Health.GetLimbs(ply)
end

local function IsSpeechImpaired(ply, body)
    if body and (body.impairedSpeech or body.disfigured) then return true end

    local limbs = GetLimbs(ply)
    local head = limbs and limbs.head
    return head and head.dislocated == true
end

local function IsBrainDamaged(body)
    if not body then return false end
    return (body.brainHealth or 100) < 82.5 or (body.strokeAmount or 0) > 20
end

local function IsUnderwater(ply, body)
    if not IsValid(ply) then return false end
    return ply:WaterLevel() >= 3 and not (body and body.hasScubaGear)
end

local function SelfTalkEnabled(ply)
    if not IsValid(ply) then return false end
    return ply:GetInfoNum("woundsys_self_talk_enabled", SELF_TALK_DEFAULT) ~= 0
end

local function PainCensored(ply)
    if not IsValid(ply) then return false end
    return ply:GetInfoNum("woundsys_pain_sounds_enabled", 1) == 0
end

local function BaseHappiness(ply, body)
    if body and body.happiness ~= nil then return body.happiness end
    if WoundSystemHappiness and WoundSystemHappiness.Get then
        return WoundSystemHappiness.Get(ply)
    end

    return IsValid(ply) and ply:GetNWFloat("WoundSystem_Happiness", 0) or 0
end

local function IsConscious(body)
    if not body or body.mindWipe then return false end
    if body.conscious ~= nil then return body.conscious == true and (body.brainHealth or 100) > 50 end
    return not body.unconscious and (body.consciousness or 100) > 30 and (body.brainHealth or 100) > 50
end

local function TotalHappiness(ply)
    if WoundSystemHappiness and WoundSystemHappiness.Total then
        return WoundSystemHappiness.Total(ply)
    end

    return IsValid(ply) and ply:GetNWFloat("WoundSystem_Happiness", 0) or 0
end

local function CanSelfTalk(ply, body)
    if not SelfTalkEnabled(ply) or not IsConscious(body) then return false end
    if (body.traumaAmount or 0) > 80 then return false end
    if TotalHappiness(ply) < -75 then return false end
    return true
end

local function PickLine(lineType, limbId, ply)
    local pool = TALK_LINES[lineType]
    if not pool or #pool <= 0 then return nil end

    local line = pool[math.random(1, #pool)]
    if limbId then
        line = string.gsub(line, "<limb>", LIMB_NAMES[limbId] or limbId)
    end

    if IsValid(ply) then
        local bloodColor = string.lower(ply:GetInfo("woundsys_blood_color") or "")
        local serverBlood = GetConVar("woundsys_blood_color")
        if bloodColor == "red" or (serverBlood and string.lower(serverBlood:GetString()) == "red") then
            line = string.gsub(line, "yellow", "red")
            line = string.gsub(line, "Yellow", "Red")
        end
    end

    return line
end

local function ProcessTalkerChatText(ply, text, force)
    if not IsValid(ply) or not ply:Alive() then return text end
    if IsCommandText(text) then return text end

    local body = GetBody(ply)
    if not body then return text end

    if body.mindWipe or (body.brainHealth or 100) <= 50 then
        return ""
    end

    if body.unconscious or (body.consciousness or 100) < 20 then
        return ""
    end

    local happiness = WoundSystemHappiness and WoundSystemHappiness.Total and WoundSystemHappiness.Total(ply) or ply:GetNWFloat("WoundSystem_Happiness", 0)
    if not force and (happiness < -75 or (body.traumaAmount or 0) > 80) then
        return ""
    end

    local result = tostring(text or "")

    if IsSpeechImpaired(ply, body) then
        result = ReplaceSomeLetters(result, FULL_MOUTH_CHARS, 0.25)
    end

    if IsBrainDamaged(body) then
        result = ApplyBrainDamageSpeech(result)
    end

    if IsUnderwater(ply, body) then
        result = ReplaceAllLetters(result, UNDERWATER_CHARS)
    end

    return result
end

local function AutoSay(ply, line, force)
    if not IsValid(ply) or not line or line == "" then return false end

    line = "\"" .. line .. "\""
    line = ProcessTalkerChatText(ply, line, force)
    if line == "" then return false end

    net.Start("WoundSystem_SelfTalkChat")
        net.WriteEntity(ply)
        net.WriteString(line)
    net.Broadcast()
    return true
end

function WoundSystem.TalkerSayLine(ply, lineType, limbId, force)
    if not IsValid(ply) or not lineType then return false end
    local line = PickLine(lineType, limbId)
    return AutoSay(ply, line, force)
end

local function FindLimb(predicate)
    return function(limbs)
        if type(limbs) ~= "table" then return nil end

        for limbId, limb in pairs(limbs) do
            if type(limb) == "table" and not limb.dismembered and predicate(limb) then
                return limbId, limb
            end
        end
    end
end

local WeakMuscleLimb = FindLimb(function(limb) return (limb.muscle or 100) < 50 end)
local SkinHurtLimb = FindLimb(function(limb) return (limb.skin or 100) < 50 end)
local InfectedLimb = FindLimb(function(limb) return (limb.infection or 0) > 5 or (limb.infectionAmount or 0) > 5 end)
local PainfulLimb = FindLimb(function(limb) return (limb.pain or 0) > 35 end)

local function IsBreathing(ply, body)
    if not body then return false end
    if body.breathing ~= nil then return body.breathing == true end

    local submerged = IsValid(ply) and ply:WaterLevel() >= 3 and not body.hasScubaGear
    return (body.respiratoryRate or 100) > 10 and not submerged
end

local function IsCriticallyDying(body, limbs)
    if not body then return false end
    if body.isCriticallyDying ~= nil then return body.isCriticallyDying == true end

    local oxygen = body.bloodOxygen or 100
    local pressure = body.bloodPressure or 120
    local bloodVolume = body.bloodVolume or 100
    local totalBleedSpeed = body.totalBleedSpeed or 0
    local fibrillation = body.fibrillationProgress or 0
    local hunger = body.hunger or 100
    local septicShock = body.septicShock or 0
    local temperature = body.temperature or 37
    local head = limbs and limbs.head
    local headMuscle = head and (head.muscle or head.muscleHealth or 100) or 100

    return (totalBleedSpeed > 0.02 and bloodVolume < 30)
        or oxygen < 50
        or (hunger < 0 and headMuscle < 25)
        or septicShock > 82.5
        or temperature < 27
        or temperature > 41.5
        or fibrillation > 60
        or pressure < 70
end

local function ShouldTalk(lineType, state, threshold, lastSensitive)
    if (state.newTalkTime or 0) <= threshold then return false end
    if lastSensitive and state.lastLineType == lineType then return false end
    return true
end

local function SelectSelfTalkLine(ply, body, limbs, state)
    local baseHappiness = BaseHappiness(ply, body)
    local totalHappiness = TotalHappiness(ply)
    local moodMult = math.Clamp(1 + baseHappiness * 0.009, 0, 1)
    local opiateReception = body.actualOpiateReception or body.opiateReception or 0
    local temperature = body.temperature or 37
    local hunger = body.hunger or 100
    local thirst = body.thirst or 100
    local stamina = body.stamina or 100
    local consciousness = body.consciousness or 100
    local avgPain = body.avgPain or body.averagePain or 0
    local breathBad = not IsBreathing(ply, body)
    local criticallyDying = IsCriticallyDying(body, limbs)
    local totalBleedSpeed = body.totalBleedSpeed or 0

    if avgPain > 80 and not PainCensored(ply) and ShouldTalk("bigpain", state, 5, false) then return "bigpain" end
    if breathBad and ShouldTalk("cantBreathe", state, 8, false) then return "cantBreathe" end
    if totalHappiness < -62 and ShouldTalk("miserable", state, 30, true) then return "miserable" end
    if criticallyDying and not PainCensored(ply) and ShouldTalk("lastmoments", state, 12, false) then return "lastmoments" end
    if opiateReception < -15 and ShouldTalk("opiatewithdrawal", state, 20, true) then return "opiatewithdrawal" end
    if hunger < 30 * moodMult and ShouldTalk("starving", state, 25, true) then return "starving" end
    if thirst < 30 and ShouldTalk("dehydrated", state, 25, true) then return "dehydrated" end
    if stamina < 25 and ShouldTalk("exhausted", state, 10, true) then return "exhausted" end
    if temperature < 31 and ShouldTalk("freezing", state, 22, true) then return "freezing" end
    if temperature > 40 and ShouldTalk("hot", state, 22, true) then return "hot" end
    if (body.brainHealth or 100) < 95 and ShouldTalk("braindamaged", state, 16, true) then return "braindamaged" end
    if totalBleedSpeed > 0.03 and ShouldTalk("bleeding", state, 35, true) then return totalBleedSpeed > 0.142 and "bleedingheavy" or "bleeding" end
    if (body.sicknessAmount or 0) > 70 and ShouldTalk("verysick", state, 35, true) then return "verysick" end
    if totalHappiness < -46 and ShouldTalk("depressed", state, 36, true) then return "depressed" end
    if stamina < 55 and ShouldTalk("exerted", state, 15, true) then return "exerted" end
    if avgPain > 35 and ShouldTalk("pain", state, 11, true) then
        local limbId = PainfulLimb(limbs)
        if limbId then return "pain", limbId end
    end

    if consciousness < 35 and ShouldTalk("verytired", state, 20, true) then return "verytired" end

    if ShouldTalk("limbinfected", state, 60, true) then
        local limbId = InfectedLimb(limbs)
        if limbId then return "limbinfected", limbId end
    end

    if ShouldTalk("limbskin", state, 60, true) then
        local limbId = SkinHurtLimb(limbs)
        if limbId then return "limbskin", limbId end
    end

    if ShouldTalk("limbmuscle", state, 70, true) then
        local limbId = WeakMuscleLimb(limbs)
        if limbId then return "limbmuscle", limbId end
    end

    if totalHappiness < -30 and ShouldTalk("gloomy", state, 45, true) then return "gloomy" end
    if consciousness < 70 and ShouldTalk("confused", state, 30, true) then return "confused" end
    if consciousness < 80 and ShouldTalk("tired", state, 50, true) then return "tired" end
    if hunger < 70 * moodMult and ShouldTalk("hungry", state, 100, true) then return "hungry" end
    if thirst < 70 and ShouldTalk("thirsty", state, 100, true) then return "thirsty" end
    if (body.dirtyness or 0) > 70 and ShouldTalk("dirty", state, 85, true) then return "dirty" end
    if (body.overEncumberance or 0) > 0 and ShouldTalk("encumbered", state, 85, true) then return "encumbered" end
    if (body.wetness or 0) > 70 and ShouldTalk("wet", state, 60, true) then return "wet" end
    if temperature < 35 and ShouldTalk("cold", state, 50, true) then return "cold" end
    if temperature > 38 and ShouldTalk("warm", state, 50, true) then return "warm" end
    if totalHappiness < -13 and ShouldTalk("sad", state, 55, true) then return "sad" end
    if baseHappiness > -30 and opiateReception > 20 and ShouldTalk("opiated", state, 30, true) then return "opiated" end
    if baseHappiness <= -30 and opiateReception > 20 and ShouldTalk("opiatedsad", state, 30, true) then return "opiatedsad" end
    if (body.sicknessAmount or 0) > 20 and ShouldTalk("sick", state, 60, true) then return "sick" end
end

hook.Add("PlayerSay", "WoundSystem_TalkerChatEffects", function(ply, text, teamChat)
    if not WoundSystemHealthEnabled() then return end

    local result = ProcessTalkerChatText(ply, text)

    if result ~= text then
        return result
    end
end)

hook.Add("EntityTakeDamage", "WoundSystem_TalkerHitByCreature", function(victim, dmginfo)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(victim) or not victim:IsPlayer() or not victim:Alive() then return end

    if dmginfo and (dmginfo:IsDamageType(DMG_BLAST) or dmginfo:IsDamageType(DMG_SONIC)) and (victim.woundsys_NextLoudTalk or 0) < CurTime() then
        if WoundSystem.TalkerSayLine(victim, "loud", nil, true) then
            victim.woundsys_NextLoudTalk = CurTime() + 12
        end
    end

    if (victim.woundsys_NextCreatureTalk or 0) > CurTime() then return end

    local attacker = dmginfo and dmginfo:GetAttacker()
    if not IsValid(attacker) or attacker == victim then return end

    local isCreature = attacker:IsNPC() or attacker:IsNextBot()
    if not isCreature then return end

    local damage = dmginfo:GetDamage() or 0
    if damage < 4 then return end

    if WoundSystem.TalkerSayLine(victim, "hitbycreature", nil, true) then
        victim.woundsys_NextCreatureTalk = CurTime() + 10
    end
end)

hook.Add("Think", "WoundSystem_SelfTalkThink", function()
    local now = CurTime()
    if (WoundSystem_NextSelfTalkTick or 0) > now then return end
    WoundSystem_NextSelfTalkTick = now + SELF_TALK_INTERVAL

    if not WoundSystemHealthEnabled() then return end

    for _, ply in ipairs(player.GetAll()) do
        local state = SelfTalkState[ply] or {newTalkTime = 0, lastLineType = "", wasConscious = true}
        SelfTalkState[ply] = state

        local body = GetBody(ply)
        local conscious = IsConscious(body)

        if conscious then
            state.newTalkTime = (state.newTalkTime or 0) + SELF_TALK_INTERVAL
            if (state.newTalkTime or 0) > 120 then
                state.lastLineType = ""
            end

            if not state.wasConscious and (body.avgPain or body.averagePain or 0) < 21 and CanSelfTalk(ply, body) then
                local wakeLine = PickLine("wakeup", nil, ply)
                if wakeLine then
                    timer.Simple(1, function()
                        if IsValid(ply) and CanSelfTalk(ply, GetBody(ply)) then
                            AutoSay(ply, wakeLine)
                        end
                    end)
                end
            end

            if CanSelfTalk(ply, body) then
                local lineType, limbId = SelectSelfTalkLine(ply, body, GetLimbs(ply), state)
                local line = PickLine(lineType, limbId, ply)
                if AutoSay(ply, line) then
                    state.lastLineType = lineType or state.lastLineType
                    state.newTalkTime = 0
                end
            end
        end

        state.wasConscious = conscious
    end
end)

hook.Add("PlayerDisconnected", "WoundSystem_TalkerSelfTalkCleanup", function(ply)
    SelfTalkState[ply] = nil
end)
