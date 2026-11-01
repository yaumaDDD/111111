WoundSystem = WoundSystem or {}

local CAS3 = WoundSystem.CAS3Locale or {}
WoundSystem.CAS3Locale = CAS3

local ITEM_KEYS = {
    ["AED"] = "aed",
    ["ADHESIVEBANDAGE"] = "adhesivebandage",
    ["ALGINATE"] = "alginate",
    ["ALCOHOL"] = "alcohol",
    ["ANALGESICGAUZE"] = "analgesicgauze",
    ["ANTIBIOTICS"] = "antibiotics",
    ["ANTIDEPRESSANTS"] = "antidepressants",
    ["BLOOD BAG"] = "bloodbag",
    ["BLOODCOAGULANT"] = "bloodcoagulant",
    ["BRUISE KIT"] = "bruisekit",
    ["CARCASSSPLINT"] = "carcasssplint",
    ["CEFTRIAXONE"] = "ceftriaxone",
    ["DISINFECTANT"] = "disinfectant",
    ["ENERGYDRINK"] = "energydrink",
    ["FENTANYL"] = "fentanyl",
    ["GAUZE"] = "bandage",
    ["HEROIN"] = "heroin",
    ["INJECTION"] = "chestdrain",
    ["ICE PACK"] = "icepack",
    ["MEDICALSUTURE"] = "medicalsuture",
    ["MORPHINE"] = "morphine",
    ["NALOXONE"] = "naloxone",
    ["NALTREXONE"] = "naltrexone",
    ["OPIUM"] = "opium",
    ["PAINCREAM"] = "paincream",
    ["PLASTICBANDAGE"] = "plasticbandage",
    ["RAG"] = "rag",
    ["RINGERSOLUTION"] = "ringersolution",
    ["RIPPEDDRESSING"] = "rippeddressing",
    ["SALINE"] = "saline",
    ["SLEEPINGPILLS"] = "sleepingpills",
    ["SPLINT"] = "splint",
    ["STERILIZEDBANDAGE"] = "sterilizedbandage",
    ["STREPTOKINASE"] = "streptokinase",
    ["TOURNIQUET"] = "tourniquet",
    ["TWEEZERS"] = "tweezers",
    ["WRENCH"] = "wrench",
    ["WOUNDGLUE"] = "woundglue"
}

CAS3.ScriptLocale = {
    main = {
        aed = "Automated external defibrillator",
        aeddsc = "Electronic defibrillator for lethal rhythm problems.\nUse on the upper torso; safer than manual defib, but slower and power-hungry.",
        adhesivebandage = "Adhesive bandages",
        adhesivebandagedsc = "Small medical dressings for light injuries.\nReduces minor bleeding.",
        alginate = "Alginate dressing",
        alginatedsc = "Biofilm-like absorbent dressing.\nSlows bleeding, helps skin recovery, and resists infection.",
        alcohol = "Bottle of alcohol",
        alcoholdsc = "Glass bottle holding 0.4L of alcohol.",
        analgesicgauze = "Medical gauze",
        analgesicgauzedsc = "Cotton gauze containing analgesic medicine.\nSlows bleeding and reduces injury pain.",
        antibiotics = "Antibiotics bottle",
        antibioticsdsc = "Bottle of antibiotic pills.\nDose: 20ml.",
        antidepressants = "Antidepressants",
        antidepressantsdsc = "A 140ml bottle of mood medication.\nDose: 20ml.",
        bloodbag = "Blood bag",
        bloodbagdsc = "A 0.75L transfusion bag with an injector.\nInjects 375ml, or draws blood when used from inventory.",
        bloodcoagulant = "Procoagulant syringe",
        bloodcoagulantdsc = "Auto-injector syringe for improving clotting.\nDose: about 34ml.",
        bruisekit = "Bruise kit",
        bruisekitdsc = "Medicine kit for muscle trauma.\nImproves muscle and skin health and helps dislocations, but does not stop bleeding.",
        carcasssplint = "Carcass splint",
        carcasssplintdsc = "A stiff tube made from joined carcasses.\nWorks as a rough splint for fractures.",
        ceftriaxone = "Ceftriaxone syringe",
        ceftriaxonedsc = "Intravenous syringe with an attached medicine vial.",
        disinfectant = "Antiseptic bottle",
        disinfectantdsc = "Spray bottle holding 0.2L of antiseptic.\nApplies 10ml per spray.",
        energydrink = "Energy drink can",
        energydrinkdsc = "A 0.25L soda can with bright markings.",
        fentanyl = "Fentanyl syringe",
        fentanyldsc = "IV syringe filled with diluted fentanyl for pain relief.\nOverdose warning: 20ml.",
        bandage = "Dressing",
        bandagedsc = "Roll of dressing used to slow bleeding, stabilize fractures, and aid skin healing.\nDoes not restore muscle health.",
        heroin = "Heroin syringe",
        heroindsc = "Large IV syringe without graduation marks or useful dose guidance.",
        chestdrain = "Chest drain",
        chestdraindsc = "Reusable thorax drain.\nReduces hemothorax buildup and only works on the chest.",
        icepack = "Ice pack",
        icepackdsc = "Self-cooling gel pack.\nSpeeds muscle recovery, reduces pain, and cools the body slightly.",
        medicalsuture = "Medical suture",
        medicalsuturedsc = "Stitches wounds closed.\nStops most bleeding immediately and improves skin condition.",
        morphine = "Morphine syringe",
        morphinedsc = "IV syringe for morphine.\nOverdose warning: 88ml.",
        naloxone = "Naloxone syringe",
        naloxonedsc = "IV syringe for opioid reversal.\nOnly part of the label is readable.",
        naltrexone = "Naltrexone bottle",
        naltrexonedsc = "Bottle of opioid-blocking pills.\nDose: 20ml.",
        opium = "Opium syringe",
        opiumdsc = "IV syringe containing opium.\nOverdose warning: 200ml.",
        paincream = "Relief cream bottle",
        paincreamdsc = "Small bottle of topical pain relief.\nDose: 10ml.",
        plasticbandage = "Plastic dressing",
        plasticbandagedsc = "Tough synthetic dressing for covering wounds and stabilizing fractures.\nDoes not restore muscle health.",
        rag = "Old rag",
        ragdsc = "Worn cloth that can work as emergency dressing.\nCan also dry you when used from inventory.",
        ringersolution = "Small IV bag",
        ringersolutiondsc = "0.7L IV fluid bag with a needle.",
        rippeddressing = "Ripped dressing",
        rippeddressingdsc = "Pile of torn cloth.\nWorks as a makeshift bandage for bleeding wounds.",
        saline = "IV bag",
        salinedsc = "0.75L IV fluid bag with a needle.",
        sleepingpills = "Sleeping pills packet",
        sleepingpillsdsc = "Blister pack containing 25ml of sleep medication.\nDose: 5ml. Brand name is missing.",
        splint = "Splint",
        splintdsc = "Sturdy board for fractures and dislocations.\nImmobilizes even healthy limbs while attached.",
        sterilizedbandage = "Sterilized dressing",
        sterilizedbandagedsc = "Clean dressing that slows bleeding, stabilizes fractures, aids skin healing, and counters infection.\nDoes not restore muscle health.",
        streptokinase = "Streptokinase syringe",
        streptokinasedsc = "Auto-injector syringe for clot breakdown.\nDose: about 34ml.",
        tourniquet = "Tourniquet",
        tourniquetdsc = "Cuts circulation to a limb and stops bleeding there without healing the wound.\nRemove it before pain and oxygen loss become severe.",
        tweezers = "Tweezers",
        tweezersdsc = "Simple metal tweezers.\nRemoves limb shrapnel cleanly and with less pain.",
        wrench = "Wrench",
        wrenchdsc = "Grip-and-torque tool.\nCorrects dislocations better than bare hands and works as a blunt tool.",
        woundglue = "Wound glue",
        woundgluedsc = "80ml tube normally filled with wound glue.\nApplies 20ml per use."
    },
    other = {
        hpbrainhealth = "Brain integrity",
        hpbrainhealthdsc = "",
        hpconsciousness = "Consciousness",
        hpconsciousnessdsc = "",
        hppain = "Total pain",
        hppaindsc = "Maximum pain across every limb.",
        hpbloodvolume = "Blood volume",
        hpbloodvolumedsc = "Total blood in the body.\nLosing around half of it is usually fatal.",
        hpbleedspeed = "Total bleeding speed",
        hpbleedspeeddsc = "",
        hpoxygenamount = "SpO2",
        hpoxygenamountdsc = "Oxygen saturation in the bloodstream.\nLow values can gradually cause complications.",
        hpimmunity = "Immunity",
        hpimmunitydsc = "How well the body fights infection.\nLow immunity lets infections progress more easily.",
        hptemperature = "Core temperature",
        hptemperaturedsc = "Internal body temperature.\nSevere hypothermia or hyperthermia can kill.",
        hpsickness = "Sickness",
        hpsicknessdsc = "",
        hphappiness = "Mood",
        hphappinessdsc = "",
        hphunger = "Hunger",
        hphungerdsc = "",
        hpthirst = "Thirst",
        hpthirstdsc = "",
        hpweight = "Body mass",
        hpweightdsc = "",
        hpstamina = "Stamina",
        hpstaminadsc = "Physical exertion",
        hprr = "Respiratory rate",
        hprrdsc = "",
        hpenergy = "Energy",
        hpenergydsc = "How sleepy you are.\nYou can sleep below 35% energy.",
        hpheartrate = "Heart rate",
        hpheartratedsc = "How fast the heart is beating.\nDo not let it reach zero.",
        hppressure = "Blood pressure",
        hppressuredsc = "Systolic and diastolic pressure.\nNormal is around 120/80.",
        hpradiation = "Radiation sickness",
        hpradiationdsc = "",
        hpselectedlimb = "Selected limb",
        hpselectedlimbdsc = "",
        hpskinhealth = "Skin health",
        hpskinhealthdsc = "Barrier against bleeding and infection.\n\nHealing is much slower below 10.",
        hpmusclehealth = "Muscle health",
        hpmusclehealthdsc = "Vitality and strength of the limb.\n\nHealing is much slower below 10.",
        hplimbinjury = "Time to heal injury",
        hplimbinjurydsc = "",
        hpinfection = "Limb infection",
        hpinfectiondsc = "",
        hplimbpain = "Limb pain",
        hplimbpaindsc = "",
        hplimbbleed = "Limb bleeding",
        hplimbbleeddsc = "",
        hplimbforce = "Limb strength",
        hplimbforcedsc = "The limb's total ability to move and exert force.",
        removetourniquet = "Remove tourniquet",
        removetourniquetdsc = "Take the tourniquet off the limb.",
        removeshrapnel = "Remove shrapnel",
        removeshrapneldsc = "Try to remove embedded shrapnel by hand.",
        removesplint = "Remove splint",
        removesplintdsc = "Take the splint off the limb.",
        fixdislocation = "Fix dislocation",
        fixdislocationdsc = "Try to force the joint back into place.",
        bandageMinigameGuide = "Click and drag the dressing around the limb to bandage.\nYou don't have to use the entire bandage.",
        syringeMinigameGuide = "Push syringe down to inject.\nMake sure to check the dosage.",
        lockpickMinigameGuide = "Click anywhere on the arch to try picking the lock.\nThe closer to the spot, the more it will turn.",
        lifepodMinigameGuide = "Match the code to open.",
        shrapnelMinigameGuide = "Pull the shrapnel out slowly.\nGoing too fast will hurt.\nTweezers bypass the speed limit.",
        dislocationMinigameGuide = "Hit the bone back into the correct spot.\nUsing a wrench hurts much less.",
        amputationMinigameGuide = "Saw through the limb to amputate.\nStop the bleeding after.",
        aedMinigameGuide = "Follow the displayed instructions.",
        manualDefibMinigameGuide = "Match the charge to the fibrillation cycle, then shock.\nRepeat if needed.",
        handCrankMinigameGuide = "Grab the handle and rotate it to charge.",
        aedstate0 = "Place pads in designated spots.",
        aedstate1 = "Analyzing pulse",
        aedstate2 = "Shock recommended.\nPress button to shock.",
        aedstate3 = "Charging",
        aedstate4 = "Shock administered.\nStart CPR on patient.",
        aedstate5 = "Shock not recommended.\nStart CPR on patient."
    },
    moodles = {
        focused = "Focused",
        focuseddsc = "Pain is being pushed into the background.",
        horrified = "Horrified",
        horrifieddsc = "Fear is overwhelming your focus.",
        impendingdoom = "Impending doom",
        impendingdoomdsc = "Something feels very wrong.",
        tachycardia = "Tachycardia",
        tachycardiadsc = "Heart rate is high.",
        bradycardia = "Bradycardia",
        bradycardiadsc = "Heart rate is low.",
        palpitations = "Palpitations",
        palpitationsdsc = "Heartbeat feels irregular.",
        stroke = "Stroke",
        strokedsc = "Brain perfusion is critically impaired.",
        cardiacarrest = "Cardiac arrest",
        cardiacarrestdsc = "The heart has stopped.",
        shock = "Shock",
        shockdsc = "Circulation is failing.",
        drugoverdose = "Drug overdose",
        drugoverdosedsc = "Drug load is dangerously high.",
        internalBleed = "Internal bleeding",
        internalBleeddsc = "Blood is being lost inside the body.",
        brokenbone = "Broken bone",
        brokenbonedsc = "A bone is fractured.",
        dislocation = "Dislocation",
        dislocationdsc = "A joint is out of place.",
        stimulated = "Stimulated",
        stimulateddsc = "Stimulants are keeping you alert.",
        badsleep = "Bad sleep",
        badsleepdsc = "Sleep quality was poor.",
        impairedspeech = "Impaired speech",
        impairedspeechdsc = "Brain damage is interfering with speech.",
        rnrs = "Neural recovery sickness",
        rnrsdsc = "Time remaining: <>.",
        amputation = "Amputation",
        amputationdsc = "One or more limbs are missing.",
        adrenaline = "Fight or flight",
        adrenalinedsc = "Adrenaline is elevated.",
        hollow = "Hollow",
        hollowdsc = "Emotional response is suppressed.",
        energized = "Energized",
        energizeddsc = "Stimulant effect remaining: <>.",
        cantbreathe = "Can't breathe",
        cantbreathedsc = "Breathing is blocked or failing.",
        concussion = "Concussion",
        concussiondsc = "The brain has been hit hard.",
        asleep = "Asleep",
        asleepdsc = "You are asleep.",
        unconscious = "Unconscious",
        unconsciousdsc = "You are not awake.",
        incapacitated = "Incapacitated",
        incapacitateddsc = "Consciousness is barely holding.",
        braindamage1 = "Brain trauma",
        braindamage1dsc = "Brain damage is causing symptoms.",
        braindamage2 = "Brain damage",
        braindamage2dsc = "Brain damage is severe.",
        braindamage3 = "Severe brain damage",
        braindamage3dsc = "The brain is in critical condition.",
        confused1 = "Lightheaded",
        confused1dsc = "Focus is slightly impaired.",
        confused2 = "Confused",
        confused2dsc = "Thinking is heavily impaired.",
        confused3 = "Incapacitated",
        confused3dsc = "Consciousness is barely holding.",
        sick1 = "Queasy",
        sick1dsc = "Sickness is building.",
        sick2 = "Sick",
        sick2dsc = "You may vomit soon.",
        sick3 = "Very sick",
        sick3dsc = "Vomiting is likely.",
        sick4 = "Severely sick",
        sick4dsc = "Sickness is overwhelming.",
        depression1 = "Sad",
        depression1dsc = "Mood is below normal.",
        depression2 = "Gloomy",
        depression2dsc = "Mood is low.",
        depression3 = "Depressed",
        depression3dsc = "Mood is very low.",
        depression4 = "Miserable",
        depression4dsc = "Mood is dangerously low.",
        happy1 = "Comfortable",
        happy1dsc = "Mood is above normal.",
        happy2 = "Content",
        happy2dsc = "Mood is good.",
        happy3 = "Happy",
        happy3dsc = "Mood is very good.",
        happy4 = "Ecstatic",
        happy4dsc = "Mood is excellent."
    }
}

for key, value in pairs({
    focused = "FOCUSED",
    focuseddsc = "Tunnel vision is taking over. Pain matters less than survival.",
    horrified = "HORRIFIED",
    horrifieddsc = "Terror is drowning out everything else. Think later; survive now.",
    impendingdoom = "Sense of impending doom",
    impendingdoomdsc = "A sudden wave of fear hits hard, like something nearby has gone silent.",
    tachycardia = "Tachycardia",
    tachycardiadsc = "Your heart rate feels abnormally high.",
    bradycardia = "Bradycardia",
    bradycardiadsc = "Your heart rate feels abnormally low.",
    palpitations = "Palpitations",
    palpitationsdsc = "Your heart is pounding hard enough to notice.",
    stroke = "Stroke",
    strokedsc = "Bleeding in the brain. Survival depends on very fast treatment.",
    cardiacarrest = "Cardiac arrest",
    cardiacarrestdsc = "The heart has stopped. Brain oxygen loss and death follow quickly.",
    thoraxdestroyed = "Lung failure",
    thoraxdestroyeddsc = "The chest is too damaged for the lungs to work properly.",
    hemothorax = "Hemothorax",
    hemothoraxdsc = "Blood is building up in the chest cavity and making breathing harder.",
    pulmonaryembolism = "Pulmonary embolism",
    pulmonaryembolismdsc = "A clot is blocking blood flow through the lungs. Thin the blood urgently.",
    shock = "Shock",
    shockdsc = "Agony is pushing the body into shock.",
    drugoverdose = "Drug overdose",
    drugoverdosedsc = "A non-opioid drug dose is high enough to cause complications.",
    internalBleed = "Internal bleeding",
    internalBleeddsc = "Blood is leaking where it should not be. Treatment is recommended.",
    brokenbone = "Fractured bone",
    brokenbonedsc = "Something is broken. Rest the limb and stabilize it.",
    dislocation = "Dislocated joint",
    dislocationdsc = "A joint is out of place. Avoid using it until corrected.",
    stimulated = "Stimulated",
    stimulateddsc = "Hard stimulants are in the bloodstream. You feel ready for now.",
    badsleep = "Bad sleep",
    badsleepdsc = "A harsh sleeping surface left you less rested and less aware.",
    impairedspeech = "Impaired speech",
    impairedspeechdsc = "Something is making communication difficult.",
    rnrs = "Rapid neuron regeneration sickness",
    rnrsdsc = "Rapid brain repair has shocked your nerves. It will fade in <>.",
    amputation = "Amputated",
    amputationdsc = "An extremity is gone. That limb's use is permanently lost.",
    adrenaline = "Adrenaline",
    adrenalinedsc = "Pain is muted and your body is on high alert.",
    hollow = "Hollow",
    hollowdsc = "",
    energized = "Energized",
    energizeddsc = "Stamina loss and sleepiness are reduced. (<>).",
    cantbreathe = "Respiratory arrest",
    cantbreathedsc = "You are suffocating. Unconsciousness and death are close if untreated.",
    concussion = "Concussed",
    concussiondsc = "Low head vitality knocked you out. You will wake when it recovers.",
    asleep = "Sleeping",
    asleepdsc = "Taking a nap.",
    unconscious = "Unconscious",
    unconsciousdsc = "Not responding to outside stimulus.",
    incapacitated = "Incapacitated",
    incapacitateddsc = "You can barely stand, think, or feel clearly.",
    highimmunity = "Immunocompetent",
    highimmunitydsc = "The immune system is working hard. Infections are much less threatening.",
    lowimmunity = "Immunocompromised",
    lowimmunitydsc = "The immune system is weakened. Infections become much more dangerous.",
    keratinbooster = "Boosted regrowth",
    keratinboosterdsc = "Claw regrowth is greatly increased. (<>).",
    rippedeyes = "Blind",
    rippedeyesdsc = "Both eyes are gone. You are relying on sound and feel.",
    rippedeye = "Half-blind",
    rippedeyedsc = "One eye is gone, narrowing your field of view and leaving a mental scar.",
    rippedjaw = "Disfigured",
    rippedjawdsc = "Severe head trauma tore away the lower jaw. Eating and speaking are much harder.",

    braindamage1 = "Cognitive impairment",
    braindamage1dsc = "Brain damage is making thought feel strange and confused.",
    braindamage2 = "Neurological damage",
    braindamage2dsc = "Serious brain damage is limiting thought and self-maintenance.",
    braindamage3 = "Severe neurophysiological deterioration",
    braindamage3dsc = "Reality is becoming difficult to understand.",
    fibrillation1 = "Arrhythmia",
    fibrillation1dsc = "Heart rhythm is abnormal and may worsen if the cause is not treated.",
    fibrillation2 = "Ventricular tachycardia",
    fibrillation2dsc = "Irregular rhythm is preventing effective pumping and may become lethal.",
    fibrillation3 = "Ventricular fibrillation",
    fibrillation3dsc = "The heart rhythm is chaotic and life-threatening. Asystole may follow.",
    hypotension1 = "Mild hypotension",
    hypotension1dsc = "Blood pressure is a little low. You feel slightly dizzy.",
    hypotension2 = "Hypotension",
    hypotension2dsc = "Blood pressure is low enough to make you pale, clammy, and unwell.",
    hypotension3 = "Severe hypotension",
    hypotension3dsc = "Blood pressure is dangerously low and you are close to fainting.",
    hypotension4 = "Circulatory collapse",
    hypotension4dsc = "Blood pressure is lethally low. Organs and brain are not being supplied.",
    hypertension1 = "Mild hypertension",
    hypertension1dsc = "Blood pressure is slightly elevated.",
    hypertension2 = "Hypertension",
    hypertension2dsc = "Blood pressure is high enough to cause headache, dizziness, and nosebleeds.",
    hypertension3 = "Severe hypertension",
    hypertension3dsc = "Blood pressure is dangerously high and complications are close.",
    hypertension4 = "Hypertensive crisis",
    hypertension4dsc = "Life-threatening blood pressure. Stroke risk is severe.",
    oxygen1 = "Mild hypoxemia",
    oxygen1dsc = "SpO2 is below 90%. It may point to an underlying problem.",
    oxygen2 = "Hypoxemia",
    oxygen2dsc = "SpO2 is below 75%, stressing the heart and starving the brain slowly.",
    oxygen3 = "Severe hypoxemia",
    oxygen3dsc = "SpO2 is below 60%. Tissue oxygen is low and arrhythmia is likely.",
    oxygen4 = "Critical hypoxemia",
    oxygen4dsc = "SpO2 is below 45%. Something has gone very wrong.",
    irradiated1 = "Uncomfortable",
    irradiated1dsc = "You feel strangely irritated and physically uncomfortable.",
    irradiated2 = "Radiation sickness",
    irradiated2dsc = "Fever, nausea, hot skin, and pain suggest serious radiation sickness.",
    irradiated3 = "Severe radiation sickness",
    irradiated3dsc = "You are horribly sick, aching, and struggling to breathe or think.",
    irradiated4 = "Chernobyl wannabe",
    irradiated4dsc = "Radiation damage is overwhelming the body.",
    pain1 = "Discomfort",
    pain1dsc = "Mild pain.",
    pain2 = "Pain",
    pain2dsc = "Moderate pain. Mood is slowly getting worse.",
    pain3 = "Severe pain",
    pain3dsc = "Intense pain is fogging your mind. Mood is dropping.",
    pain4 = "Agony",
    pain4dsc = "Overwhelming pain is compromising movement and thought.",
    overdose1 = "Opiated",
    overdose1dsc = "Relaxed and numb.",
    overdose2 = "Drugged",
    overdose2dsc = "Very calm, a little tired, and breathing feels heavier.",
    overdose3 = "Highly drugged",
    overdose3dsc = "Breathing is difficult, but euphoria is masking the danger.",
    overdose4 = "Opioid overdose",
    overdose4dsc = "Respiratory failure from opioids. Suffocation is imminent.",
    withdrawal1 = "Opioid craving",
    withdrawal1dsc = "You badly want another dose.",
    withdrawal2 = "Withdrawal",
    withdrawal2dsc = "The body is desperate, nauseous, and miserable. Treatment is recommended.",
    withdrawal3 = "Severe withdrawal",
    withdrawal3dsc = "Shaking and desperation are making it hard to keep together.",
    withdrawal4 = "Dying of withdrawal",
    withdrawal4dsc = "Withdrawal is threatening circulation. Watch for fibrillation.",
    bleeding1 = "Minor bleeding",
    bleeding1dsc = "Blood is oozing from a small wound. Immediate danger is low.",
    bleeding2 = "Bleeding",
    bleeding2dsc = "A moderate wound is bleeding. Treatment is recommended.",
    bleeding3 = "Heavy bleeding",
    bleeding3dsc = "A large amount of blood is being lost. Untreated, this is likely lethal.",
    bleeding4 = "Catastrophic bleeding",
    bleeding4dsc = "Blood loss is extreme and time is running out.",
    exertion1 = "Slightly exerted",
    exertion1dsc = "Mild physical strain. (<>%)",
    exertion2 = "Exerted",
    exertion2dsc = "Movement and work are getting uncomfortable. (<>%)",
    exertion3 = "Highly exerted",
    exertion3dsc = "You can barely move from exertion. (<>%)",
    exertion4 = "Totally exhausted",
    exertion4dsc = "You can barely breathe. (<>%)",
    infected1 = "Infection",
    infected1dsc = "The site is warm and swollen. Treat it before it spreads.",
    infected2 = "Painful infection",
    infected2dsc = "The wound is swollen, painful, and leaking badly.",
    infected3 = "Severe infection",
    infected3dsc = "The infection is spreading fast and may become sepsis.",
    infected4 = "Life-threatening infection",
    infected4dsc = "The limb is necrotic and infection is spreading through the body.",
    venom1 = "Mild toxicosis",
    venom1dsc = "A small amount of hemotoxin is in the blood.",
    venom2 = "Toxicosis",
    venom2dsc = "Hemotoxin is impairing clotting and damaging blood cells.",
    venom3 = "Severe toxicosis",
    venom3dsc = "A large toxin load is clogging and damaging the blood.",
    venom4 = "Toxic crisis",
    venom4dsc = "The blood is becoming too damaged to sustain life.",
    hunger1 = "Peckish",
    hunger1dsc = "Could do with a bite to eat.",
    hunger2 = "Hungry",
    hunger2dsc = "Uncomfortably hungry and slightly weaker than usual.",
    hunger3 = "Very hungry",
    hunger3dsc = "Extremely hungry and desperate for food.",
    hunger4 = "Starving",
    hunger4dsc = "The body is wasting away. Organ failure is close.",
    hunger5 = "Satiated",
    hunger5dsc = "Well fed. Weight loss and mobility are reduced, mood improves slightly.",
    hunger6 = "Full",
    hunger6dsc = "Stuffed with food. More could make you sick.",
    thirst1 = "Thirsty",
    thirst1dsc = "Feeling a little thirsty.",
    thirst2 = "Dehydrated",
    thirst2dsc = "Body water is low. You are very thirsty.",
    thirst3 = "Parched",
    thirst3dsc = "The body is drying out and thirst is hard to ignore.",
    thirst4 = "Desiccated",
    thirst4dsc = "Blood volume is dangerously low and thick from dehydration.",
    overhydrated1 = "Slaked",
    overhydrated1dsc = "Thirst is fully satisfied for now. Blood pressure is increased.",
    overhydrated2 = "Overhydrated",
    overhydrated2dsc = "You drank too much. Movement is slightly impaired and blood pressure is up.",
    overhydrated3 = "Water-intoxicated",
    overhydrated3dsc = "Excess water is swelling cells and pressuring the brain.",
    sick1 = "Queasy",
    sick1dsc = "Minor sickness and discomfort.",
    sick2 = "Nauseous",
    sick2dsc = "Stomach confusion and discomfort. Vomiting is more likely.",
    sick3 = "Sick",
    sick3dsc = "Major discomfort, tiredness, and strong vomiting risk.",
    sick4 = "Grossly sick",
    sick4dsc = "Dangerously sick. Weak, confused, and in serious discomfort.",
    wet1 = "Damp",
    wet1dsc = "Your fur feels a little wet.",
    wet2 = "Wet",
    wet2dsc = "Wetness is lowering comfort and temperature.",
    wet3 = "Soaked",
    wet3dsc = "Dripping wet. Comfort and temperature are much worse.",
    wet4 = "Water-logged",
    wet4dsc = "Completely drenched and weighed down by water.",
    trauma1 = "Anxious",
    trauma1dsc = "Something bad happened, and your brain remembers it.",
    trauma2 = "Scared",
    trauma2dsc = "Recent events left you shaky and unwilling to repeat them.",
    trauma3 = "Traumatized",
    trauma3dsc = "Panic and intrusive memories are taking over.",
    trauma4 = "Shell shocked",
    trauma4dsc = "Horrified, helpless, and almost unable to speak.",
    hypoventilation1 = "Mild hypoventilation",
    hypoventilation1dsc = "Respiratory rate is reduced.",
    hypoventilation2 = "Hypoventilation",
    hypoventilation2dsc = "Breathing is slow enough to lower blood oxygen over time.",
    sepsis1 = "Sepsis",
    sepsis1dsc = "A widespread infection is causing confusion, fever, and low pressure.",
    sepsis2 = "Severe sepsis",
    sepsis2dsc = "Organ dysfunction signs are appearing. Septic shock may follow.",
    sepsis3 = "Septic shock",
    sepsis3dsc = "Sepsis is collapsing circulation.",
    confused1 = "Confused",
    confused1dsc = "Feeling disoriented and slightly dizzy.",
    confused2 = "Very confused",
    confused2dsc = "Confusion and dizziness are making the world hard to follow.",
    confused3 = "Fainting",
    confused3dsc = "Barely conscious and close to collapse.",
    tired1 = "Drowsy",
    tired1dsc = "Getting sleepy.",
    tired2 = "Tired",
    tired2dsc = "It is nap time.",
    tired3 = "Very tired",
    tired3dsc = "It is really nap time.",
    tired4 = "Half-asleep",
    tired4dsc = "Barely awake and close to exhaustion.",
    cold1 = "Chilly",
    cold1dsc = "A little too cold for comfort.",
    cold2 = "Cold",
    cold2dsc = "Unpleasantly cold. The body is slowing down.",
    cold3 = "Hypothermia",
    cold3dsc = "Temperature is dangerously low and the body is shutting down.",
    cold4 = "Freezing to death",
    cold4dsc = "Cold and confusion are pulling you toward sleep.",
    hot1 = "Warm",
    hot1dsc = "A little too warm for comfort.",
    hot2 = "Hot",
    hot2dsc = "Unpleasantly hot.",
    hot3 = "Hyperthermia",
    hot3dsc = "Dangerously hot and struggling to continue.",
    hot4 = "Heatstroke",
    hot4dsc = "Heat is damaging cells and threatening organs.",
    happy1 = "Satisfied",
    happy1dsc = "Content with the current situation.",
    happy2 = "Excited",
    happy2dsc = "Looking forward to whatever comes next.",
    happy3 = "Happy",
    happy3dsc = "You have found some peace here.",
    happy4 = "Gleeful",
    happy4dsc = "Everything feels possible right now.",
    depression1 = "Feeling down",
    depression1dsc = "The weight of the situation is starting to sink in.",
    depression2 = "Gloomy",
    depression2dsc = "Motivation is low and things look bleak.",
    depression3 = "Depressed",
    depression3dsc = "Desperation is wearing down the will to act.",
    depression4 = "Miserable",
    depression4dsc = "Hopelessness is overwhelming.",
    clawdamage1 = "Dulled claws",
    clawdamage1dsc = "Claws are worn down. Rest your hands or use a tool.",
    clawdamage2 = "Broken claws",
    clawdamage2dsc = "Claws are badly damaged. Continuing without tools may hurt your hands.",
    deaf2 = "Impaired hearing",
    deaf2dsc = "High frequencies are harder to hear. Rest your ears.",
    deaf3 = "Hearing loss",
    deaf3dsc = "Sound is muffled and echoing. This may take time to recover.",
    deaf4 = "Severe hearing loss",
    deaf4dsc = "You can barely hear anything. Recovery will take a while.",
    dirty1 = "Dirty",
    dirty1dsc = "Consider cleaning yourself. (<>%)",
    dirty2 = "Very dirty",
    dirty2dsc = "Poor hygiene is weakening your infection resistance. (<>%)",
    encumbered1 = "Heavy load",
    encumbered1dsc = "Carrying a bit too much. <> encumbrance.",
    encumbered2 = "Encumbered",
    encumbered2dsc = "Carrying too much. Stamina and mobility are reduced. <> encumbrance.",
    encumbered3 = "Very encumbered",
    encumbered3dsc = "Carrying far too much. Stamina and mobility are heavily reduced. <> encumbrance.",
    encumbered4 = "Hampered",
    encumbered4dsc = "You can barely move under this load. <> encumbrance.",
    overweight1 = "Chubby",
    overweight1dsc = "Try to lose a few kilos.",
    overweight2 = "Overweight",
    overweight2dsc = "Unhealthily overweight. Clumsier and tiring faster.",
    overweight3 = "Fat",
    overweight3dsc = "Dangerously heavy, clumsy, and prone to exhaustion.",
    overweight4 = "Obese",
    overweight4dsc = "Life-threateningly overweight with high heart failure risk.",
    underweight1 = "Underweight",
    underweight1dsc = "Try to gain a few kilos.",
    underweight2 = "Skinny",
    underweight2dsc = "Unhealthily underweight. Weaker with lower carry capacity.",
    underweight3 = "Malnourished",
    underweight3dsc = "Dangerously thin, frail, tired, and weak.",
    underweight4 = "Emaciated",
    underweight4dsc = "Excessively thin and at high heart failure risk."
}) do
    CAS3.ScriptLocale.moodles[key] = value
end

CAS3.ScriptTalkLocale = {
    tired = {
        "*yawn*",
        "I'm getting drowsy...",
        "I could use a nap.",
        "Sleep sounds good right now."
    },
    verytired = {
        "I can barely keep my eyes open...",
        "I'm going to collapse...",
        "Need... sleep...",
        "I have to lie down..."
    },
    confused = {
        "What's happening...?",
        "My head...",
        "I can't focus...",
        "Stay awake... stay awake..."
    },
    wakeup = {
        "What's happening...?",
        "Eyes open...",
        "Back to it...",
        "Still here..."
    },
    sick = {
        "My stomach hurts...",
        "I feel sick.",
        "I feel nauseous...",
        "I might vomit..."
    },
    verysick = {
        "I'm going to throw up...",
        "My stomach hurts so bad...",
        "I feel poisoned...",
        "I can't focus through this sickness..."
    },
    vomit = {
        "Ugh... that was awful...",
        "There goes my stomach...",
        "I feel empty...",
        "That was disgusting..."
    },
    vomitblood = {
        "That was blood...",
        "I'm throwing up blood...",
        "Something is bleeding inside...",
        "That wasn't normal vomit..."
    },
    braindamaged = {
        "Something is wrong with my head...",
        "Thinking feels wrong...",
        "My thoughts won't stay together...",
        "I can't make sense of this..."
    },
    cantBreathe = {
        "I can't breathe!",
        "Air... I need air...",
        "My chest won't move right...",
        "I'm suffocating..."
    },
    exhausted = {
        "I'm exhausted...",
        "I need to catch my breath.",
        "My body won't keep up...",
        "I can barely move..."
    },
    exerted = {
        "I'm getting tired...",
        "Need to slow down...",
        "I'm wearing myself out.",
        "My muscles are burning..."
    },
    bleeding = {
        "I'm bleeding...",
        "Need to cover this wound.",
        "That's more blood than I like...",
        "I should stop the bleeding."
    },
    bleedingheavy = {
        "I'm losing too much blood!",
        "This bleeding is bad...",
        "I need pressure on this now!",
        "Blood's pouring out..."
    },
    depressed = {
        "I don't know how much longer I can do this...",
        "Everything feels pointless...",
        "I feel hollow...",
        "I need something good to happen."
    },
    gloomy = {
        "This place is getting to me...",
        "I feel awful...",
        "Hard to keep going...",
        "I miss feeling okay."
    },
    sad = {
        "I'm not feeling great...",
        "This is miserable...",
        "I need a distraction...",
        "I feel down."
    },
    miserable = {
        "I can't do this...",
        "I want out of here...",
        "Everything hurts inside...",
        "I feel hopeless."
    },
    opiatewithdrawal = {
        "I need another dose...",
        "Withdrawal is tearing me up...",
        "I'm shaking so bad...",
        "Anything to make this stop..."
    },
    opiated = {
        "That took the edge off...",
        "Everything feels softer...",
        "Pain's fading...",
        "I can breathe through this..."
    },
    opiatedsad = {
        "At least it hurts less...",
        "I still feel awful, just farther away...",
        "The pain is quiet for now...",
        "This calm won't last..."
    },
    limbinfected = {
        "My <limb> feels infected...",
        "My <limb> is warm and swollen...",
        "I need to clean my <limb>.",
        "This infection on my <limb> is getting worse..."
    },
    limbskin = {
        "The skin on my <limb> is in bad shape...",
        "My <limb> needs covering.",
        "This wound on my <limb> is ugly...",
        "I need to treat the skin on my <limb>."
    },
    limbmuscle = {
        "My <limb> feels weak...",
        "I can barely use my <limb>.",
        "The muscle in my <limb> feels ruined...",
        "My <limb> won't move right."
    },
    pain = {
        "My <limb> hurts...",
        "Pain in my <limb>...",
        "I need to stop using my <limb>.",
        "My <limb> is killing me..."
    },
    bigpain = {
        "Everything hurts!",
        "I can't think through the pain!",
        "It hurts so much...",
        "Make it stop..."
    },
    warm = {
        "It's getting hot...",
        "I'm overheating a little...",
        "Need to cool down...",
        "Too warm for comfort."
    },
    hot = {
        "I'm burning up...",
        "This heat is awful...",
        "I need shade or cold now...",
        "I feel cooked..."
    },
    cold = {
        "It's cold...",
        "I'm shivering...",
        "Need to warm up...",
        "This chill is getting bad."
    },
    freezing = {
        "I'm freezing...",
        "I can't stop shaking...",
        "The cold is making me sleepy...",
        "Need warmth now..."
    },
    dirty = {
        "I need to wash off...",
        "I'm filthy...",
        "This grime can't be healthy...",
        "I should clean myself."
    },
    encumbered = {
        "I'm carrying too much...",
        "This load is slowing me down.",
        "Too heavy...",
        "I need to drop something."
    },
    wet = {
        "I'm soaked...",
        "My fur is wet...",
        "This water is weighing me down.",
        "I need to dry off."
    }
}
CAS3._BaseLocale = nil

local function IsTable(value)
    if istable then return istable(value) end
    return type(value) == "table"
end

local function Trim(value)
    if string.Trim then return string.Trim(tostring(value or "")) end
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function NormalizeLocaleText(value)
    if type(value) ~= "string" then return value end

    value = string.gsub(value, "\r\n", "\n")
    value = string.gsub(value, "\r", "\n")
    value = string.gsub(value, "\\n", "\n")
    value = string.gsub(value, "\\r", "\n")
    value = string.gsub(value, "\\t", "\t")

    return value
end

local function NormalizeItemId(itemId)
    if WoundSystem.NormalizeItemId then return WoundSystem.NormalizeItemId(itemId) end
    return string.upper(Trim(itemId))
end

local function LoadBaseLocale()
    if CAS3._BaseLocale ~= nil then return CAS3._BaseLocale or nil end

    CAS3._BaseLocale = IsTable(CAS3.ScriptLocale) and CAS3.ScriptLocale or false
    return CAS3._BaseLocale or nil
end

local function LocaleSection(section)
    local base = LoadBaseLocale()
    local data = base and base[section]
    return IsTable(data) and data or nil
end

function CAS3.Main(key)
    local data = LocaleSection("main")
    return NormalizeLocaleText(data and data[key] or nil)
end

function CAS3.Other(key)
    local data = LocaleSection("other")
    return NormalizeLocaleText(data and data[key] or nil)
end

function CAS3.Moodle(key)
    local data = LocaleSection("moodles")
    return NormalizeLocaleText(data and data[key] or nil)
end

local function MergeSection(base, sectionName, source)
    if not IsTable(source) then return end

    base[sectionName] = IsTable(base[sectionName]) and base[sectionName] or {}

    for key, value in pairs(source) do
        if type(value) == "string" then
            base[sectionName][key] = NormalizeLocaleText(value)
        end
    end
end

function CAS3.MergeBaseLocale(locale)
    if not IsTable(locale) then return false end

    local base = IsTable(CAS3._BaseLocale) and CAS3._BaseLocale or {}
    MergeSection(base, "main", locale.main)
    MergeSection(base, "other", locale.other)
    MergeSection(base, "moodles", locale.moodles)
    CAS3._BaseLocale = base
    return true
end

function CAS3.ApplyItemText(item)
    if not IsTable(item) then return item end

    local localeKey = ITEM_KEYS[NormalizeItemId(item.id)]
    if not localeKey then return item end

    item.title = CAS3.Main(localeKey) or item.title
    item.desc = CAS3.Main(localeKey .. "dsc") or item.desc
    return item
end

function CAS3.ApplyAllItemText()
    local items = WoundSystem.Items
    if not items or not IsTable(items.Stored) then return end

    for _, item in pairs(items.Stored) do
        CAS3.ApplyItemText(item)
    end
end

function CAS3.WrapItemRegistry()
    local items = WoundSystem.Items
    if not items or not items.Register then return end

    items._CAS3LocaleBaseRegister = items._CAS3LocaleBaseRegister or items.Register
    if items._CAS3LocaleWrapped then return end

    function items.Register(itemId, data)
        local item = items._CAS3LocaleBaseRegister(itemId, data)
        return CAS3.ApplyItemText(item)
    end

    items._CAS3LocaleWrapped = true
end

function CAS3.ApplyHealthTooltips(tooltips)
    if not IsTable(tooltips) then return end

    for key, entry in pairs(tooltips) do
        if key ~= "hpecg" and IsTable(entry) then
            entry[1] = CAS3.Other(key) or entry[1]
            entry[2] = CAS3.Other(key .. "dsc") or entry[2]
        end
    end
end

function CAS3.ApplyMinigameText(clip)
    if not IsTable(clip) then return end

    if IsTable(clip.Guides) then
        for key in pairs(clip.Guides) do
            clip.Guides[key] = CAS3.Other(key) or clip.Guides[key]
        end
    end
end

function CAS3.ApplyAEDStateText(stateText)
    if not IsTable(stateText) then return end

    for state = 0, 5 do
        stateText[state] = CAS3.Other("aedstate" .. state) or stateText[state]
    end
end

function CAS3.ApplyClientTextOverrides()
    if not CLIENT then return end

    CAS3.ApplyAllItemText()

    if WoundSystemCasTooltipText then
        CAS3.ApplyHealthTooltips(WoundSystemCasTooltipText)
    end

    if WoundSystem.MinigameClip then
        CAS3.ApplyMinigameText(WoundSystem.MinigameClip)
    end

    if WoundSystem.Moodles then
        WoundSystem.Moodles.NextBuild = 0
    end

    hook.Run("WoundSystem_CAS3LocaleReady", CAS3)
end

function CAS3.ApplyTalkLineOverrides(talkLines)
    if not IsTable(talkLines) then return end

    local overrides = CAS3.ScriptTalkLocale
    if not IsTable(overrides) then return end

    for category in pairs(talkLines) do
        local lines = overrides[category]
        local override = {}

        if IsTable(lines) then
            for _, value in ipairs(lines) do
                override[#override + 1] = NormalizeLocaleText(value)
            end
        else
            local prefixes = {
                "dialogue_experiment_" .. tostring(category),
                "dialogue_expie_" .. tostring(category)
            }
            local index = 1

            while true do
                local value

                for _, prefix in ipairs(prefixes) do
                    value = overrides[prefix .. index] or overrides[string.lower(prefix) .. index]
                    if value then break end
                end

                if not value then break end
                override[#override + 1] = NormalizeLocaleText(value)
                index = index + 1
            end
        end

        if #override > 0 then
            talkLines[category] = override
        end
    end
end

local function SeverityKey(prefix, intensity)
    return prefix .. tostring(math.Clamp(math.floor(tonumber(intensity) or 0) + 1, 1, 4))
end

local function ReplacementFromDesc(template, current)
    current = tostring(current or "")

    local timer = string.match(current, "(%d+:%d+:%d+)") or string.match(current, "(%d+:%d+)")
    if timer then return timer end

    local number = string.match(current, "([%d%.]+)%%")
    if number then
        if string.find(template, "<>%", 1, true) then return number end
        return number .. "%"
    end

    return string.match(current, "([%d%.]+)") or ""
end

local function FillMoodleDesc(template, current)
    template = NormalizeLocaleText(template)
    if not string.find(template, "<>", 1, true) then return template end
    return NormalizeLocaleText(string.gsub(template, "<>", ReplacementFromDesc(template, current)))
end

local function PickMoodleKey(moodle)
    local id = string.lower(tostring(moodle.id or ""))
    local icon = string.lower(tostring(moodle.icon or ""))
    local title = string.lower(tostring(moodle.title or ""))
    local intensity = tonumber(moodle.intensity) or 0

    if id == "focused" then return "focused" end
    if id == "horrified" then return icon == "impendingdoom" and "impendingdoom" or "horrified" end
    if id == "tachycardia" then return "tachycardia" end
    if id == "bradycardia" then return "bradycardia" end
    if id == "palpitations" then return "palpitations" end
    if id == "laststand" then return "laststand" end
    if id == "stroke" then return "stroke" end
    if id == "cardiacarrest" then return "cardiacarrest" end
    if id == "thoraxdestroyed" then return "thoraxdestroyed" end
    if id == "hemothorax" then return "hemothorax" end
    if id == "pulmonaryembolism" then return "pulmonaryembolism" end
    if id == "shock" then return "shock" end
    if id == "drugoverdose" then return "drugoverdose" end
    if id == "internalbleed" then return "internalBleed" end
    if id == "brokenbone" then return "brokenbone" end
    if id == "dislocation" then return "dislocation" end
    if id == "stimulants" then return "stimulated" end
    if id == "badsleep" then return "badsleep" end
    if id == "impairedspeech" then return "impairedspeech" end
    if id == "rnrs" then return "rnrs" end
    if id == "amputation" then return "amputation" end
    if id == "fightorflight" then return "adrenaline" end
    if id == "hollow" then return "hollow" end
    if id == "energized" then return "energized" end

    if id == "braindamage" then
        if string.find(title, "severe", 1, true) then return "braindamage3" end
        if string.find(title, "damage", 1, true) then return "braindamage2" end
        return "braindamage1"
    end

    if id == "arrythmia" then
        if string.find(title, "fibrillation", 1, true) then return "fibrillation3" end
        if string.find(title, "arrhythmia", 1, true) then return "fibrillation2" end
        return "fibrillation1"
    end

    if id == "hypotension" then return SeverityKey("hypotension", intensity) end
    if id == "hypertension" then return SeverityKey("hypertension", intensity) end
    if id == "oxygen" then return SeverityKey("oxygen", intensity) end
    if id == "irradiated" then return SeverityKey("irradiated", intensity) end
    if id == "pain" then return SeverityKey("pain", intensity) end
    if id == "overdose" then return SeverityKey("overdose", intensity) end
    if id == "withdrawal" then return SeverityKey("withdrawal", intensity) end
    if id == "bleeding" then return SeverityKey("bleeding", intensity) end
    if id == "exertion" then return SeverityKey("exertion", intensity) end
    if id == "infected" then return SeverityKey("infected", intensity) end
    if id == "venom" then return SeverityKey("venom", intensity) end
    if id == "hunger" then
        if intensity >= 5 then return "hunger6" end
        if intensity >= 4 then return "hunger5" end
        return SeverityKey("hunger", intensity)
    end

    if id == "thirst" then return SeverityKey("thirst", intensity) end

    if id == "overhydrated" then
        if intensity >= 3 then return "overhydrated3" end
        if intensity >= 1 then return "overhydrated2" end
        return "overhydrated1"
    end

    if id == "sick" then return SeverityKey("sick", intensity) end
    if id == "wet" then return SeverityKey("wet", intensity) end
    if id == "trauma" then return SeverityKey("trauma", intensity) end

    if id == "breathing" then
        return icon == "hypoventilation" and SeverityKey("hypoventilation", intensity) or "cantbreathe"
    end

    if id == "sepsis" then
        return "sepsis" .. tostring(math.Clamp(math.floor(intensity), 1, 3))
    end

    if id == "consciousness" then
        if icon == "concussion" then return "concussion" end
        if icon == "asleep" then return "asleep" end
        if icon == "unconscious" then return "unconscious" end
        if string.find(title, "incapacitated", 1, true) then return "incapacitated" end
        if intensity >= 2 then return "confused3" end
        if intensity >= 1 then return "confused2" end
        return "confused1"
    end

    if id == "tired" then
        return "tired" .. tostring(math.Clamp(math.floor(intensity) + 1, 1, 4))
    end

    if id == "temperature" then
        if icon == "cold" then return SeverityKey("cold", intensity) end
        return SeverityKey("hot", intensity)
    end

    if id == "mood" then
        if string.find(icon, "happy", 1, true) then
            return "happy" .. tostring(math.Clamp(math.floor(intensity) - 3, 1, 4))
        end
        return "depression" .. tostring(math.Clamp(math.floor(intensity) + 1, 1, 4))
    end

    if id == "clawdamage" then
        return intensity >= 1 and "clawdamage2" or "clawdamage1"
    end

    if id == "hearingloss" then
        return "deaf" .. tostring(math.Clamp(math.floor(intensity) + 2, 2, 4))
    end

    if id == "dirty" then
        return intensity >= 1 and "dirty2" or "dirty1"
    end

    if id == "encumbered" then return SeverityKey("encumbered", intensity) end

    if id == "immunity" then
        return string.find(icon, "highimmunity", 1, true) and "highimmunity" or "lowimmunity"
    end

    if id == "keratinbooster" then return "keratinbooster" end

    if id == "weight" then
        if string.find(icon, "overweight", 1, true) then return SeverityKey("overweight", intensity) end
        return SeverityKey("underweight", intensity)
    end

    if id == "disfigurement" then
        if string.find(title, "both", 1, true) or string.find(title, "eyes", 1, true) then return "rippedeyes" end
        if string.find(title, "eye", 1, true) then return "rippedeye" end
        return "rippedjaw"
    end

    return nil
end

function CAS3.ApplyMoodleText(moodle)
    if not IsTable(moodle) then return moodle end

    local key = PickMoodleKey(moodle)
    if not key then return moodle end

    moodle.title = CAS3.Moodle(key) or moodle.title

    local desc = CAS3.Moodle(key .. "dsc")
    if desc then
        moodle.desc = FillMoodleDesc(desc, moodle.desc)
    end

    return moodle
end

CAS3.WrapItemRegistry()
CAS3.ApplyAllItemText()
