// GatiVani Antigravity UI Prototype Logic
document.addEventListener('DOMContentLoaded', () => {

  // ==================== MOCK DATA DATABASE ====================
  const MOCK_ARTICLES = [
    {
      id: "a01",
      title: "కరీంనగర్‌ కలెక్టరేట్‌ లో జంతుశాల ప్రారంభం",
      preview: "శాతవాహన ఫార్మసీ కళాశాలలో ఉపకులపతి ఆచార్య యు.ఉమేశ్‌కుమార్‌ 'జంతుశాల'ను ప్రారంభించారు.",
      content: "రాష్ట్ర విద్యాశాఖ వారోత్సవాల సందర్భంగా సోమవారం కరీంనగర్‌ మానేరు డ్యాం సమీపంలోని శాతవాహన ఫార్మసీ కళాశాలలో ఉపకులపతి ఆచార్య యు.ఉమేశ్‌కుమార్‌ 'జంతుశాల'ను ప్రారంభించారు. అనంతరం ఆయన మాట్లాడుతూ.. జంతువులను సంరక్షించటానికి, ప్రీ క్లినికల్‌ రీసెర్చ్‌ చేయటానికి, బీఫార్మసీ, ఎంఫార్మసీలలో కొత్త ఆవిష్కరణలకు ఇది ఉపయోగపడుతుందన్నారు. రిజిస్ర్రార్‌ సతీష్‌కుమార్‌ మాట్లాడుతూ.. పరిశోధనలకు జంతుశాల కీలకమన్నారు. ప్రిన్సిపల్‌ శ్రీశైలం, వర్సిటీ ఆచార్యులు పాల్గొన్నారు.",
      category: "State",
      page: 1,
      duration: 92,
      durationText: "1:32 నిమిషాలు",
      speaker: "Priya",
      thumbnail: "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=150&q=80",
      wideCover: "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=600&q=80",
      aiSummary: [
        "కరీంనగర్‌ శాతవాహన ఫార్మసీ కళాశాలలో జంతుశాల ప్రారంభం",
        "జంతువుల సంరక్షణకు మరియు ప్రీ-క్లినికల్‌ రీసెర్చ్‌కు ఇది తోడ్పడుతుంది",
        "బీఫార్మసీ, ఎంఫార్మసీ పరిశోధనలలో సరికొత్త ఆవిష్కరణలకు మార్గం"
      ],
      sentences: [
        "కరీంనగర్‌ కలెక్టరేట్‌ లో జంతుశాల ప్రారంభం.",
        "రాష్ట్ర విద్యాశాఖ వారోత్సవాల సందర్భంగా శాతవాహన ఫార్మసీ కళాశాలలో జంతుశాల ప్రారంభమైంది.",
        "ఉపకులపతి ఆచార్య యు.ఉమేశ్‌కుమార్‌ దీనిని ప్రారంభించారు.",
        "అనంతరం ఆయన మాట్లాడుతూ.. జంతువులను సంరక్షించటానికి ఇది ఉపయోగపడుతుందన్నారు.",
        "బీఫార్మసీ, ఎంఫార్మసీలలో కొత్త ఆవిష్కరణలకు ఈ జంతుశాల ఎంతో దోహదపడుతుంది.",
        "రిజిస్ర్రార్‌ సతీష్‌కుమార్‌ మాట్లాడుతూ.. పరిశోధనలకు జంతుశాల కీలకమన్నారు.",
        "ఈ కార్యక్రమంలో ప్రిన్సిపల్‌ శ్రీశైలం, వర్సిటీ ఆచార్యులు పాల్గొన్నారు."
      ]
    },
    {
      id: "a02",
      title: "వ్యవసాయంలో ఫర్టిగేషన్‌ తో పెట్టుబడి ఆదా, దిగుబడి హెచ్చు",
      preview: "రసాయన ఎరువులను వెదజల్లటం కాకుండా బిందుసేద్య పద్ధతి ద్వారా అందించడం వల్ల ఎరువుల వినియోగం తగ్గుతుంది.",
      content: "రసాయన ఎరువులను వెదజల్లటం, మొక్కల మొదళ్లలో పోయటం వంటి సాంప్రదాయ పద్ధతుల వల్ల ఎరువులు మొక్కలకు తగినంతగా అందకపోవటం, గాలికి ఆవిరికావటం తదితర నష్టాలు సంభవిస్తున్నాయి. దీనికి విరుద్ధంగా బిందుసేద్య పద్ధతి ద్వారా నీటిలో కరిగే స్వభావం గల ఎరువులను మొక్కల వేర్లకు నేరుగా అందించినప్పుడు పంటల్లో నాణ్యత పెరిగి దిగుబడి 29-69 శాతం వరకు పెరుగుతుంది. ఎరువుల మోతాదును 15-25 శాతం వరకు తగ్గించుకోవచ్చు, కూలీల అవసరం కూడా తగ్గుతుంది.",
      category: "Agriculture",
      page: 2,
      duration: 124,
      durationText: "2:04 నిమిషాలు",
      speaker: "Kavitha",
      thumbnail: "https://images.unsplash.com/photo-1500937386664-56d1dfef3854?auto=format&fit=crop&w=150&q=80",
      wideCover: "https://images.unsplash.com/photo-1500937386664-56d1dfef3854?auto=format&fit=crop&w=600&q=80",
      aiSummary: [
        "బిందుసేద్యం ద్వారా ఎరువులు అందించడం వల్ల మోతాదు ఆదా",
        "పంటల నాణ్యత పెరిగి దిగుబడి 29-69 శాతం పెరిగే అవకాశం",
        "కూలీల ఖర్చు తగ్గడం మరియు నేల కోత నివారించడం దీని ప్రత్యేకత"
      ],
      sentences: [
        "వ్యవసాయంలో ఫర్టిగేషన్‌ తో పెట్టుబడి ఆదా, దిగుబడి హెచ్చు.",
        "రసాయన ఎరువులను వెదజల్లటం వల్ల ఎరువులు మొక్కలకు తగినంతగా అందకపోవటం వంటి నష్టాలు ఉన్నాయి.",
        "బిందుసేద్య పద్ధతి ద్వారా ఎరువులను నేరుగా అందించే ప్రక్రియను ఫర్టిగేషన్‌ అంటారు.",
        "ఈ విధానంలో పంటల్లో నాణ్యత పెరిగి దిగుబడి 29 నుండి 69 శాతం వరకు పెరుగుతుంది.",
        "ఎరువుల మోతాదును 15-25 శాతం వరకు తగ్గించవచ్చని ఉద్యానశాఖ అధికారి తెలిపారు.",
        "ఈ పద్ధతి వల్ల నేల కోతకు గురికాకుండా ఉంటుంది మరియు కూలీల ఖర్చు కూడా బాగా తగ్గుతుంది."
      ]
    },
    {
      id: "a03",
      title: "కూరగాయల సాగులో లక్షల లాభాలు గడిస్తున్న రైతు రాజు",
      preview: "కేవీకే శాస్త్రవేత్తల సలహాలతో వంగ, టమాట సాగు చేస్తూ ఆదర్శంగా నిలుస్తున్న పెద్దపల్లి రైతు.",
      content: "పెద్దపల్లి మండలం బ్రాహ్మణపల్లి గ్రామానికి చెందిన రైతు ఓదెల రాజు వరి, పత్తి సాగు వదిలి కూరగాయల సాగు ప్రారంభించి రికార్డు లాభాలు సాధిస్తున్నాడు. రామగిరి కృషి విజ్ఞాన కేంద్రం శాస్త్రవేత్తల సూచనలతో అర ఎకరంలో వంగ, టమాట సాగు చేసాడు. కేవలం యాభై వేల ఖర్చుతో రెండు లక్షల రూపాయల దిగుబడి సాధించాడు. సమగ్ర కీటక యాజమాన్య పద్ధతులు పాటించడంతో రసాయన మందుల వాడకం తగ్గి నాణ్యమైన కూరగాయలు పండించగలిగానని రాజు ఆనందం వ్యక్తం చేశాడు.",
      category: "Business",
      page: 2,
      duration: 110,
      durationText: "1:50 నిమిషాలు",
      speaker: "Shubh",
      thumbnail: "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=150&q=80",
      wideCover: "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=600&q=80",
      aiSummary: [
        "సాంప్రదాయ వరి వదిలి వంగ, టమాటా సాగుతో విజయం సాధించిన రాజు",
        "యాభై వేల ఖర్చుతో రెండు లక్షల లాభం సాధించిన రైతు",
        "రసాయన మందులు తగ్గించి సమగ్ర కీటక యాజమాన్యం పాటించడం"
      ],
      sentences: [
        "కూరగాయల సాగులో లక్షల లాభాలు గడిస్తున్న రైతు రాజు.",
        "పెద్దపల్లి మండలం బ్రాహ్మణపల్లి గ్రామానికి చెందిన రైతు ఓదెల రాజు కూరగాయల సాగుతో రికార్డు లాభాలు సాధిస్తున్నాడు.",
        "గతంలో వరి, పత్తి సాగు చేసేవాడినని, అయితే తగిన ఆదాయం లేక ఉద్యాన పంటల వైపు మొగ్గు చూపానని తెలిపాడు.",
        "కృషి విజ్ఞాన కేంద్రం శాస్త్రవేత్తల సూచనలతో వంగ, టమాట సాగు ప్రారంభించాడు.",
        "సమగ్ర యాజమాన్య పద్ధతులు పాటించడంతో పెట్టుబడి ఖర్చు తగ్గి ఆదాయం పెరిగింది.",
        "పంట నాణ్యత బాగుండటంతో మార్కెట్లో క్వింటాలు వంకాయలకు 800 రూపాయల వరకు పలికిందని హర్షం వ్యక్తం చేసాడు."
      ]
    },
    {
      id: "a04",
      title: "ఆర్థిక వ్యవస్థ పుంజుకోవాలంటే ఏం చేయాలి?",
      preview: "ఆర్థిక వ్యవస్థ పుంజుకోవడానికి ఎనిమిది కీలక సంస్కరణలు అత్యవసరమని విశ్లేషకులు భావిస్తున్నారు.",
      content: "ఆర్థిక వ్యవస్థ పుంజుకోవాలంటే జాతీయ ఉత్పాదకతను పెంచడం ద్వారా ఉద్యోగాల సృష్టి జరగాలి. ద్రవ్య విధానం మరియు బ్యాంకింగ్ రంగాల పటిష్టత చాలా ముఖ్యం. పరిశ్రమలకు తక్కువ వడ్డీతో రుణాలు అందించడం ద్వారా కొత్త పెట్టుబడులను ఆకర్షించవచ్చు. గ్రామీణ ప్రాంతాలలో కొనుగోలు శక్తిని పెంచడానికి ప్రత్యేక పథకాలు అమలు చేయాల్సి ఉంటుంది. ఎగుమతులను ప్రోత్సహించడంతో పాటు దేశీయ మార్కెట్లను సుసంపన్నం చేయడమే ప్రధాన కర్తవ్యం.",
      category: "Editorial",
      page: 2,
      duration: 96,
      durationText: "1:36 నిమిషాలు",
      speaker: "Aditya",
      isEditorial: true,
      columnist: {
        name: "ఆచార్య రవిశంకర్",
        role: "సీనియర్ ఆర్థిక విశ్లేషకులు",
        avatar: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=150&q=80"
      },
      thumbnail: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=150&q=80",
      wideCover: "https://images.unsplash.com/photo-1454165804606-c3d57bc86b40?auto=format&fit=crop&w=600&q=80",
      aiSummary: [
        "ఆర్థిక రంగం పుంజుకోవడానికి ఎనిమిది కీలక సంస్కరణలు అవసరం",
        "జాతీయ ఉత్పాదకతను పెంచడం ద్వారా ఉద్యోగాల సృష్టి",
        "ద్రవ్య విధానం మరియు బ్యాంకింగ్ రంగాల పటిష్టత"
      ],
      sentences: [
        "ఆర్థిక వ్యవస్థ పుంజుకోవాలంటే ఏం చేయాలి?",
        "ఆర్థిక రంగ విశ్లేషణ ప్రకారం ఎనిమిది కీలక రంగాలు పుంజుకోవాల్సి ఉంటుంది.",
        "మొదటిది జాతీయ ఉత్పాదకతను విపరీతంగా పెంచడం ద్వారా ఉద్యోగాలు సృష్టించడం.",
        "రెండవది ద్రవ్య విధానం మరియు బ్యాంకింగ్ రంగాన్ని మరింత పటిష్టపరచడం.",
        "గ్రామీణ ప్రాంతాలలో ప్రజల కొనుగోలు శక్తిని పెంచడానికి తగిన చర్యలు తీసుకోవాలి.",
        "రవాణా మరియు మౌలిక వసతుల కల్పనలో పెట్టుబడులను వేగవంతం చేయాలి."
      ]
    },
    {
      id: "a05",
      title: "రాష్ట్రంలో భారీ వర్షాలు: అప్రమత్తంగా ఉండాలని అధికారుల హెచ్చరిక",
      preview: "బంగాళాఖాతంలో ఏర్పడిన ద్రోణి కారణంగా రాష్ట్రవ్యాప్తంగా రాగల మూడు రోజులు వర్షాలు కురుస్తాయి.",
      content: "బంగాళాఖాతంలో ఏర్పడిన ఉపరితల ఆవర్తనం కారణంగా రాగల మూడు రోజుల్లో రాష్ట్రవ్యాప్తంగా భారీ నుండి అతి భారీ వర్షాలు కురిసే అవకాశం ఉందని వాతావరణ శాఖ హెచ్చరించింది. ముఖ్యంగా తీర ప్రాంత జిల్లాలు మరియు లోతట్టు ప్రాంత ప్రజలు అప్రమత్తంగా ఉండాలని సూచించారు. నదుల ఉధృతి మరియు కొండచరియలు విరిగిపడే ప్రమాదం ఉన్న చోట్ల ప్రత్యేక నిఘా ఏర్పాటు చేసారు. అత్యవసర సేవల విభాగాలను అప్రమత్తం చేసినట్లు విపత్తుల కమిషనర్ తెలిపారు.",
      category: "State",
      page: 1,
      duration: 90,
      durationText: "1:30 నిమిషాలు",
      speaker: "Kavitha",
      thumbnail: "https://images.unsplash.com/photo-1534274988757-a28bf1a57c17?auto=format&fit=crop&w=150&q=80",
      wideCover: "https://images.unsplash.com/photo-1534274988757-a28bf1a57c17?auto=format&fit=crop&w=600&q=80",
      aiSummary: [
        "రాష్ట్రంలో రాగల మూడు రోజుల్లో భారీ వర్షాలు కురిసే అవకాశం ఉంది",
        "తీర ప్రాంత జిల్లాలు మరియు లోతట్టు ప్రాంత ప్రజలు అప్రమత్తం కావాలి",
        "విపత్తు నిర్వహణ బృందాలు మరియు అత్యవసర సేవలు పూర్తి సిద్ధం"
      ],
      sentences: [
        "రాష్ట్రంలో భారీ వర్షాలు: అప్రమత్తంగా ఉండాలని అధికారుల హెచ్చరిక.",
        "బంగాళాఖాతంలో ఏర్పడిన ఆవర్తనం కారణంగా రాగల మూడు రోజులు భారీ వర్షాలు కురిసే అవకాశం ఉంది.",
        "ముఖ్యంగా లోతట్టు ప్రాంతాలు మరియు నదీ పరివాహక ప్రాంత ప్రజలు అప్రమత్తంగా ఉండాలి.",
        "జిల్లా కలెక్టరేట్లలో ఇరవై నాలుగు గంటల కంట్రోల్ రూములు ఏర్పాటు చేసారు.",
        "విపత్తు నిర్వహణ బృందాలు సహాయక చర్యలకు సిద్ధంగా ఉన్నట్లు అధికారులు తెలిపారు."
      ]
    },
    {
      id: "a06",
      title: "నేటి నుండే అంతర్జాతీయ చిత్రోత్సవాలు",
      preview: "నగరంలోని ఐదు ప్రధాన థియేటర్లలో ప్రపంచ స్థాయి అత్యుత్తమ చిత్రాల ప్రదర్శన.",
      content: "హైదరాబాద్ ఫిలిం చాంబర్ ఆధ్వర్యంలో నేటి నుండి వారం రోజుల పాటు అంతర్జాతీయ చలనచిత్రోత్సవాలు జరగనున్నాయి. మొత్తం 25 దేశాల నుండి ఎంపిక చేసిన 80 అత్యుత్తమ కళాఖండాలను ఇక్కడ ప్రదర్శిస్తారు. ప్రారంభోత్సవ వేడుకలకు సినీ ప్రముఖులతో పాటు సాంస్కృతిక శాఖా మంత్రి హాజరుకానున్నారు. సినిమా టికెట్లను ఆన్‌లైన్ ద్వారా బుక్ చేసుకునే సదుపాయం కల్పించారు.",
      category: "Entertainment",
      page: 3,
      duration: 85,
      durationText: "1:25 నిమిషాలు",
      speaker: "Kavitha",
      thumbnail: "https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?auto=format&fit=crop&w=150&q=80",
      wideCover: "https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?auto=format&fit=crop&w=600&q=80",
      aiSummary: [
        "చిత్ర చాంబర్ ఆధ్వర్యంలో వారం రోజుల పండుగ",
        "ఇరవై ఐదు దేశాల నుండి ఎనభై ఉత్తమ సినిమాలు ప్రదర్శన",
        "ఆన్‌లైన్ బుకింగ్ సీట్ల వివరాలు ప్రారంభం"
      ],
      sentences: [
        "నేటి నుండే అంతర్జాతీయ చిత్రోత్సవాలు.",
        "హైదరాబాద్ ఫిలిం చాంబర్ ఆధ్వర్యంలో వారం రోజుల పాటు ఈ ఉత్సవాలు జరుగుతాయి.",
        "మొత్తం ఇరవై ఐదు దేశాల నుండి ఎనభై సినిమాలు ప్రదర్శనకు ఎంపికయ్యాయి.",
        "ప్రారంభోత్సవానికి పలువురు సినీ ప్రముఖులు మరియు మంత్రి హాజరవుతున్నారు.",
        "ఆన్‌లైన్ ద్వారా సీట్లు రిజర్వ్ చేసుకునేందుకు బుకింగ్స్ ఓపెన్ అయ్యాయి."
      ]
    }
  ];� లక్షల రూపాయల దిగుబడి సాధించాడు. సమగ్ర కీటక యాజమాన్య పద్ధతులు పాటించడంతో రసాయన మందుల వాడకం తగ్గి నాణ్యమైన కూరగాయలు పండించగలిగానని రాజు ఆనందం వ్యక్తం చేశాడు.",
      category: "Business",
      page: 2,
      duration: 110,
      speaker: "Shubh",
      sentences: [
        "కూరగాయల సాగులో లక్షల లాభాలు గడిస్తున్న రైతు రాజు.",
        "పెద్దపల్లి మండలం బ్రాహ్మణపల్లి గ్రామానికి చెందిన రైతు ఓదెల రాజు కూరగాయల సాగుతో రికార్డు లాభాలు సాధిస్తున్నాడు.",
        "గతంలో వరి, పత్తి సాగు చేసేవాడినని, అయితే తగిన ఆదాయం లేక ఉద్యాన పంటల వైపు మొగ్గు చూపానని తెలిపాడు.",
        "కృషి విజ్ఞాన కేంద్రం శాస్త్రవేత్తల సూచనలతో వంగ, టమాట సాగు ప్రారంభించాడు.",
        "సమగ్ర యాజమాన్య పద్ధతులు పాటించడంతో పెట్టుబడి ఖర్చు తగ్గి ఆదాయం పెరిగింది.",
        "పంట నాణ్యత బాగుండటంతో మార్కెట్లో క్వింటాలు వంకాయలకు 800 రూపాయల వరకు పలికిందని హర్షం వ్యక్తం చేసాడు."
      ]
    },
    {
      id: "a04",
      title: "రాష్ట్ర బడ్జెట్ లో విద్యాశాఖకు భారీ కేటాయింపులు",
      preview: "రానున్న ఆర్థిక సంవత్సరంలో మౌలిక సదుపాయాల కల్పనకు ప్రభుత్వం ప్రాధాన్యత ఇవ్వనుంది.",
      content: "రాష్ట్ర శాసనసభలో ప్రవేశపెట్టిన వార్షిక బడ్జెట్‌లో విద్యా రంగానికి అత్యంత ప్రాధాన్యత కల్పించారు. ప్రభుత్వ పాఠశాలలు మరియు కళాశాలల్లో డిజిటల్ తరగతి గదుల ఏర్పాటుకు నిధులు కేటాయించారు. అలాగే, పేద విద్యార్థులకు ఉచిత ల్యాప్‌టాప్‌లు మరియు ఉపకార వేతనాలు అందించే కార్యక్రమాన్ని బలోపేతం చేయనున్నారు. రానున్న విద్యాసంవత్సరం నాటికి అన్ని ప్రభుత్వ పాఠశాలల్లో మంచినీరు, మరుగుదొడ్ల సౌకర్యాలు వంద శాతం పూర్తి చేయడమే లక్ష్యంగా పెట్టుకున్నట్లు ఆర్థిక మంత్రి తెలిపారు.",
      category: "Politics",
      page: 1,
      duration: 105,
      speaker: "Priya",
      sentences: [
        "రాష్ట్ర బడ్జెట్ లో విద్యాశాఖకు భారీ కేటాయింపులు.",
        "రాష్ట్ర శాసనసభలో ప్రవేశపెట్టిన బడ్జెట్‌లో విద్యా రంగానికి పెద్దపీట వేశారు.",
        "ప్రభుత్వ పాఠశాలల్లో డిజిటల్ తరగతి గదుల ఏర్పాటుకు ప్రత్యేక నిధులు కేటాయించారు.",
        "పేద విద్యార్థులకు ఉచిత ల్యాప్‌టాప్‌లు మరియు స్కాలర్‌షిప్‌లు అందించనున్నారు.",
        "ఆర్థిక మంత్రి బడ్జెట్ ప్రసంగంలో ఈ వివరాలు ప్రకటించారు.",
        "అన్ని పాఠశాలల్లో మౌలిక సదుపాయాలను వంద శాతం మెరుగుపరచడమే లక్ష్యమన్నారు."
      ]
    },
    {
      id: "a05",
      title: "జనవరి 15 నాటికి గూగుల్ డెవలపర్స్ సదస్సు",
      preview: "హైదరాబాద్ ఐటీ హబ్‌లో ఆర్టిఫిషియల్ ఇంటెలిజెన్స్ అంశాలపై కీలక చర్చలు జరగనున్నాయి.",
      content: "నగరంలో ప్రతిష్టాత్మక ఐటీ కన్వెన్షన్ సెంటర్‌లో వచ్చే నెల 15 నుండి అంతర్జాతీయ గూగుల్ డెవలపర్స్ సదస్సు జరగనుంది. ఈ సదస్సులో వివిధ దేశాల నుండి సుమారు 2000 మంది సాఫ్ట్‌వేర్ ఇంజనీర్లు మరియు పరిశోధకులు పాల్గొననున్నారు. ప్రధానంగా జనరేటివ్ ఏఐ (Generative AI) మరియు మెషిన్ లెర్నింగ్ రంగంలో వస్తున్న పెను మార్పులపై చర్చించనున్నారు. స్థానిక ఐటీ రంగానికి ఇది కొత్త ఊపునిస్తుందని పరిశ్రమ వర్గాలు ఆశాభావం వ్యక్తం చేస్తున్నాయి.",
      category: "Sci-Tech",
      page: 3,
      duration: 98,
      speaker: "Aditya",
      sentences: [
        "జనవరి పదిహేను నాటికి గూగుల్ డెవలపర్స్ సదస్సు.",
        "హైదరాబాద్ ఐటీ హబ్‌లో అంతర్జాతీయ సదస్సు ఏర్పాట్లు పూర్తయ్యాయి.",
        "ఈ సదస్సులో వివిధ దేశాల నుండి సాఫ్ట్‌వేర్ నిపుణులు పాల్గొంటున్నారు.",
        "ముఖ్యంగా ఆర్టిఫిషియల్ ఇంటెలిజెన్స్ అడ్వాన్స్‌మెంట్లపై ఇక్కడ ప్రసంగాలు ఉంటాయి.",
        "దేశీయ స్టార్టప్స్ మరియు ఐటీ పరిశ్రమకు ఇది ఒక మంచి వేదిక కానుంది."
      ]
    },
    {
      id: "a06",
      title: "నేటి నుండే అంతర్జాతీయ చిత్రోత్సవాలు",
      preview: "నగరంలోని ఐదు ప్రధాన థియేటర్లలో ప్రపంచ స్థాయి అత్యుత్తమ చిత్రాల ప్రదర్శన.",
      content: "హైదరాబాద్ ఫిలిం చాంబర్ ఆధ్వర్యంలో నేటి నుండి వారం రోజుల పాటు అంతర్జాతీయ చలనచిత్రోత్సవాలు జరగనున్నాయి. మొత్తం 25 దేశాల నుండి ఎంపిక చేసిన 80 అత్యుత్తమ కళాఖండాలను ఇక్కడ ప్రదర్శిస్తారు. ప్రారంభోత్సవ వేడుకలకు సినీ ప్రముఖులతో పాటు సాంస్కృతిక శాఖా మంత్రి హాజరుకానున్నారు. సినిమా టికెట్లను ఆన్‌లైన్ ద్వారా బుక్ చేసుకునే సదుపాయం కల్పించారు.",
      category: "Entertainment",
      page: 3,
      duration: 85,
      speaker: "Kavitha",
      sentences: [
        "నేటి నుండే అంతర్జాతీయ చిత్రోత్సవాలు.",
        "హైదరాబాద్ ఫిలిం చాంబర్ ఆధ్వర్యంలో వారం రోజుల పాటు ఈ ఉత్సవాలు జరుగుతాయి.",
        "మొత్తం ఇరవై ఐదు దేశాల నుండి ఎనభై సినిమాలు ప్రదర్శనకు ఎంపికయ్యాయి.",
        "ప్రారంభోత్సవానికి పలువురు సినీ ప్రముఖులు మరియు మంత్రి హాజరవుతున్నారు.",
        "ఆన్‌లైన్ ద్వారా సీట్లు రిజర్వ్ చేసుకునేందుకు బుకింగ్స్ ఓపెన్ అయ్యాయి."
      ]
    }
  ];

  // Localized Strings Dictionaries
  const LOCALIZATION = {
    'en': {
      'Home': 'Home',
      'Search': 'Search',
      'Library': 'Library',
      'Listen': 'Listen',
      'Listen to briefing': 'Listen to briefing',
      'Upload': 'Upload',
      'Recently played': 'Recently played',
      'Browse by section': 'Browse by section',
      'All articles': 'All articles',
      'All': 'All',
      'Play': 'Play',
      'Play all': 'Play all',
      'Sections': 'Sections',
      'Pages': 'Pages',
      'Page': 'Page',
      'TODAY\'S EDITION': 'TODAY\'S EDITION',
      'articles': 'articles',
      'stories': 'stories',
      'story': 'story',
      'TODAY': 'TODAY',
      'SEARCH': 'SEARCH',
      'LIBRARY': 'LIBRARY',
      'NOW NARRATING': 'NOW NARRATING',
      'Select an article to play': 'Select an article to play',
      'No source': 'No source',
      'Popular Categories': 'Popular Categories',
      'Search articles, topics...': 'Search articles, topics...',
      'History & Recents': 'History & Recents',
      'Clear': 'Clear',
      'Upload Newspaper Edition': 'Upload Newspaper Edition',
      'Select a newspaper scan PDF or JPEG page to run layout extraction and audio synthesis.': 'Select a newspaper scan PDF or JPEG page to run layout extraction and audio synthesis.',
      'Drag & drop file here or click to browse': 'Drag & drop file here or click to browse',
      'Cancel': 'Cancel',
      'Start Processing': 'Start Processing'
    },
    'te': {
      'Home': 'హోమ్',
      'Search': 'సెర్చ్',
      'Library': 'లైబ్రరీ',
      'Listen': 'వినండి',
      'Listen to briefing': 'సంక్షిప్తం వినండి',
      'Upload': 'అప్‌లోడ్',
      'Recently played': 'ఇటీవల విన్నవి',
      'Browse by section': 'విభాగాల వారీగా',
      'All articles': 'అన్ని వార్తలు',
      'All': 'అన్నీ',
      'Play': 'ప్లే',
      'Play all': 'అన్నీ ప్లే',
      'Sections': 'విభాగాలు',
      'Pages': 'పేజీలు',
      'Page': 'పేజీ',
      'TODAY\'S EDITION': 'నేటి సంచిక',
      'articles': 'వార్తలు',
      'stories': 'కథనాలు',
      'story': 'కథనం',
      'TODAY': 'నేడు',
      'SEARCH': 'శోధన',
      'LIBRARY': 'లైబ్రరీ',
      'NOW NARRATING': 'ప్రస్తుతం వినిపిస్తున్నది',
      'Select an article to play': 'వినడానికి ఒక కథనాన్ని ఎంచుకోండి',
      'No source': 'మూలాధారం లేదు',
      'Popular Categories': 'జనాదరణ పొందిన విభాగాలు',
      'Search articles, topics...': 'వార్తలు, శీర్షికల కోసం వెతకండి...',
      'History & Recents': 'చరిత్ర మరియు ఇటీవల విన్నవి',
      'Clear': 'తుడిచివేయి',
      'Upload Newspaper Edition': 'వార్తాపత్రికను అప్‌లోడ్ చేయండి',
      'Select a newspaper scan PDF or JPEG page to run layout extraction and audio synthesis.': 'వార్తాపత్రిక లేఅవుట్ మరియు ఆడియోను రూపొందించడానికి పిడిఎఫ్ లేదా జెపెగ్ ఫైల్ ఎంచుకోండి.',
      'Drag & drop file here or click to browse': 'ఫైల్‌ను ఇక్కడ లాగి వదలండి లేదా బ్రౌజ్ చేయడానికి క్లిక్ చేయండి',
      'Cancel': 'రద్దు చేయి',
      'Start Processing': 'ప్రాసెస్ ప్రారంభించు'
    }
  };

  // State Management Variables
  let currentLanguage = 'en'; // 'en' or 'te'
  let activeTab = 'today';    // 'today', 'search', 'library'
  let activeLayoutView = 'tiles'; // 'tiles' or 'list'
  let currentTheme = 'dark'; // 'dark' or 'light'
  
  // Playback State
  let currentPlayingArticle = null;
  let isPlaying = false;
  let playTimeElapsed = 0; // seconds
  let playbackTimer = null;
  let activeSentenceIndex = 0;
  let playbackSpeed = 1.0;
  
  // History State (Persisted in localStorage for preview)
  let historyList = JSON.parse(localStorage.getItem('antigravity_history')) || [
    { id: "a01", playedAt: new Date(Date.now() - 600000).toISOString() },
    { id: "a03", playedAt: new Date(Date.now() - 3600000).toISOString() }
  ];
  let favoritesList = JSON.parse(localStorage.getItem('antigravity_favorites')) || [];

  // ==================== DOM ELEMENTS ====================
  const tabViews = document.querySelectorAll('.tab-view');
  const navItems = document.querySelectorAll('.nav-item');
  const langToggleBtn = document.getElementById('lang-toggle-btn');
  const langOptions = document.querySelectorAll('.lang-option');
  const articlesContainer = document.getElementById('articles-container');
  const marqueeTrack = document.getElementById('recent-marquee');
  
  // View Toggles
  const btnViewTiles = document.getElementById('view-tiles');
  const btnViewList = document.getElementById('view-list');
  
  // Search Elements
  const searchInput = document.getElementById('search-input');
  const clearSearchBtn = document.getElementById('clear-search');
  const searchSuggestions = document.getElementById('search-suggestions');
  const searchResultsList = document.getElementById('search-results-list');
  const suggestionTiles = document.querySelectorAll('.suggest-tile');
  
  // Library Elements
  const libraryHistoryList = document.getElementById('library-history-list');
  const clearHistoryBtn = document.getElementById('clear-history');
  
  // Player Elements
  const miniPlayer = document.getElementById('global-mini-player');
  const miniPlayerProgress = document.getElementById('mini-progress-fill');
  const miniPlayerTitle = document.querySelector('#mini-player-info .title');
  const miniPlayerSubtitle = document.querySelector('#mini-player-info .subtitle');
  const miniPlayerToggle = document.getElementById('player-toggle');
  const miniPlayerPrev = document.getElementById('player-prev');
  const miniPlayerNext = document.getElementById('player-next');
  
  // Full Player Elements
  const lyricsPlayer = document.getElementById('lyrics-player');
  const closePlayerBtn = document.getElementById('close-player');
  const toggleFavoriteBtn = document.getElementById('toggle-favorite');
  const favIcon = document.querySelector('.fav-icon');
  const unfavIcon = document.querySelector('.unfav-icon');
  const lyricsLinesContainer = document.getElementById('lyrics-lines-container');
  const playerTimeElapsed = document.getElementById('player-time-elapsed');
  const playerTimeTotal = document.getElementById('player-time-total');
  const progressSlider = document.getElementById('progress-slider');
  const fullPlayerToggle = document.getElementById('full-toggle');
  const fullPlayerPrev = document.getElementById('full-prev');
  const fullPlayerNext = document.getElementById('full-next');
  const playerSpeedBtn = document.getElementById('player-speed-btn');
  const suggestedSpeaker = document.getElementById('suggested-speaker');
  const speakerNameText = document.querySelector('.speaker-name');
  
  // Upload Elements
  const uploadTrigger = document.getElementById('upload-trigger');
  const uploadModal = document.getElementById('upload-modal');
  const closeUploadModal = document.getElementById('close-upload-modal');
  const fileDropZone = document.getElementById('file-drop-zone');
  const realFileInput = document.getElementById('real-file-input');
  const startProcessBtn = document.getElementById('start-process');
  const uploadProgressContainer = document.getElementById('upload-progress-container');
  const uploadProgressText = document.getElementById('upload-progress-text');
  const uploadProgressPercent = document.getElementById('upload-progress-percent');
  const uploadProgressInner = document.getElementById('upload-progress-inner');

  // Menu Elements
  const menuDrawer = document.getElementById('menu-drawer');
  const menuTriggerBtn = document.getElementById('menu-trigger-btn');
  const closeMenuBtn = document.getElementById('close-menu');
  const optLangEn = document.getElementById('opt-lang-en');
  const optLangTe = document.getElementById('opt-lang-te');
  const optThemeDark = document.getElementById('opt-theme-dark');
  const optThemeLight = document.getElementById('opt-theme-light');
  const menuSpeedOptions = document.getElementById('menu-speed-options');
  const menuSignInBtn = document.getElementById('menu-signin-btn');
  const menuSignUpBtn = document.getElementById('menu-signup-btn');
  const menuProfileName = document.getElementById('menu-profile-name');
  const menuProfileSub = document.getElementById('menu-profile-sub');
  const menuAccountActions = document.getElementById('menu-account-actions');

  // ==================== INITIALIZATION ====================
  function init() {
    renderTabViews();
    renderRecentMarquee();
    renderMainGrid();
    setupNavigation();
    setupLanguage();
    setupToggles();
    setupSearch();
    setupPlayback();
    setupUpload();
    setupLibrary();
    setupMenu();
  }

  // ==================== LOCALIZATION HELPER ====================
  function tr(key) {
    return LOCALIZATION[currentLanguage][key] || key;
  }

  function sectionLabel(engSection) {
    const sectionTe = {
      'State': 'రాష్ట్రం',
      'National': 'జాతీయం',
      'International': 'అంతర్జాతీయం',
      'District': 'జిల్లా',
      'Politics': 'రాజకీయాలు',
      'Editorial': 'సంపాదకీయం',
      'Business': 'వాణిజ్యం',
      'Sports': 'క్రీడలు',
      'Health': 'ఆరోగ్యం',
      'Sci-Tech': 'సైన్స్-టెక్',
      'Education': 'విద్య',
      'Agriculture': 'వ్యవసాయం',
      'Entertainment': 'వినోదం',
      'Devotional': 'భక్తి',
      'Trending': 'ట్రెండింగ్',
      'News': 'వార్తలు'
    };
    return currentLanguage === 'te' ? (sectionTe[engSection] || engSection) : engSection;
  }

  function translateUIChrome() {
    // Translate text nodes with data-en/data-te properties
    document.querySelectorAll('[data-en]').forEach(el => {
      const en = el.getAttribute('data-en');
      const te = el.getAttribute('data-te');
      el.textContent = currentLanguage === 'te' ? te : en;
    });

    // Translate placeholders
    document.querySelectorAll('[data-en-placeholder]').forEach(el => {
      const en = el.getAttribute('data-en-placeholder');
      const te = el.getAttribute('data-te-placeholder');
      el.placeholder = currentLanguage === 'te' ? te : en;
    });

    // Refresh dynamic layouts
    renderRecentMarquee();
    if (activeLayoutView === 'tiles') {
      renderMainGrid();
    } else {
      renderMainList();
    }
    renderSearchSuggestions();
    renderLibraryHistory();
    updateMiniPlayerUI();
  }

  // ==================== NAVIGATION TABS ====================
  function setupNavigation() {
    navItems.forEach(item => {
      item.addEventListener('click', () => {
        const tab = item.getAttribute('data-tab');
        
        // Update nav UI active class
        navItems.forEach(nav => nav.classList.remove('active'));
        item.classList.add('active');
        
        // Show current tab view, hide others
        activeTab = tab;
        renderTabViews();
      });
    });
  }

  function renderTabViews() {
    tabViews.forEach(view => {
      view.classList.remove('active');
      if (view.id === `tab-${activeTab}`) {
        view.classList.add('active');
      }
    });

    // Refresh contents if switching
    if (activeTab === 'library') {
      renderLibraryHistory();
    }
  }

  // ==================== HOME SCREEN RENDERERS ====================
  function renderRecentMarquee() {
    marqueeTrack.innerHTML = '';
    
    // We display items twice to create the seamless loop marquee effect
    const marqueeList = [...MOCK_ARTICLES, ...MOCK_ARTICLES];
    
    marqueeList.forEach((article, idx) => {
      const card = document.createElement('div');
      card.className = 'marquee-card';
      card.innerHTML = `
        <span class="category">${sectionLabel(article.category).toUpperCase()}</span>
        <h4 class="title">${article.title}</h4>
        <div class="play-row">
          <svg viewBox="0 0 24 24" width="14" height="14"><path fill="currentColor" d="M8 5v14l11-7z"/></svg>
          <span>${tr('Play')}</span>
        </div>
      `;
      card.addEventListener('click', () => {
        playArticle(article);
      });
      marqueeTrack.appendChild(card);
    });
  }

  function renderMainGrid() {
    articlesContainer.className = 'grid-layout';
    articlesContainer.innerHTML = '';
    
    // Group articles count by category
    const categories = {};
    MOCK_ARTICLES.forEach(a => {
      categories[a.category] = (categories[a.category] || 0) + 1;
    });

    Object.keys(categories).forEach(cat => {
      const tile = document.createElement('div');
      tile.className = `section-tile category-${cat.toLowerCase()}`;
      tile.innerHTML = `
        <div class="section-name">${sectionLabel(cat)}</div>
        <div class="count">${categories[cat]} ${categories[cat] === 1 ? tr('story') : tr('stories')}</div>
        <div class="play-icon-btn">
          <svg viewBox="0 0 24 24"><path fill="currentColor" d="M8 5v14l11-7z"/></svg>
        </div>
      `;

      // Tap body -> drill down to list of section
      tile.addEventListener('click', (e) => {
        if (e.target.closest('.play-icon-btn')) {
          // Play the category playlist
          const catList = MOCK_ARTICLES.filter(a => a.category === cat);
          playPlaylist(catList);
        } else {
          // Toggle list view and pre-fill search with category
          activeLayoutView = 'list';
          btnViewTiles.classList.remove('active');
          btnViewList.classList.add('active');
          renderMainList(cat);
        }
      });
      
      articlesContainer.appendChild(tile);
    });
  }

  function renderMainList(filterCategory = null) {
    articlesContainer.className = 'list-layout';
    articlesContainer.innerHTML = '';

    let list = MOCK_ARTICLES;
    if (filterCategory) {
      list = MOCK_ARTICLES.filter(a => a.category === filterCategory);
      
      // Add a header showing filter category + back button
      const filterHeader = document.createElement('div');
      filterHeader.className = 'flex-between';
      filterHeader.style.padding = '4px 0';
      filterHeader.innerHTML = `
        <span class="badge" style="font-size: 11px;">FILTERED BY: ${sectionLabel(filterCategory).toUpperCase()}</span>
        <button id="clear-category-filter" style="background:transparent; border:none; color:var(--accent); font-size:12px; font-weight:600; cursor:pointer;">Show All</button>
      `;
      articlesContainer.appendChild(filterHeader);
      
      setTimeout(() => {
        document.getElementById('clear-category-filter').addEventListener('click', () => {
          renderMainList();
        });
      }, 0);
    }

    list.forEach(article => {
      const card = document.createElement('div');
      card.className = 'article-card';
      card.setAttribute('data-article-id', article.id);
      card.innerHTML = `
        <div class="article-card-left">
          <span class="category-tag">${sectionLabel(article.category)} • P${article.page}</span>
          <h4 class="headline">${article.title}</h4>
          <p class="snippet">${article.preview}</p>
        </div>
        <div class="article-card-play-btn">
          <svg viewBox="0 0 24 24"><path fill="currentColor" d="M8 5v14l11-7z"/></svg>
        </div>
      `;
      card.addEventListener('click', (e) => {
        const isCurrent = currentPlayingArticle && currentPlayingArticle.id === article.id;
        if (isCurrent && e.target.closest('.article-card-play-btn')) {
          togglePlayback();
        } else {
          playArticle(article);
        }
      });
      articlesContainer.appendChild(card);
    });

    syncArticlePlayingStates();
  }

  function setupToggles() {
    btnViewTiles.addEventListener('click', () => {
      activeLayoutView = 'tiles';
      btnViewList.classList.remove('active');
      btnViewTiles.classList.add('active');
      renderMainGrid();
    });

    btnViewList.addEventListener('click', () => {
      activeLayoutView = 'list';
      btnViewTiles.classList.remove('active');
      btnViewList.classList.add('active');
      renderMainList();
    });

    // Play Briefing playlist button
    document.getElementById('play-briefing').addEventListener('click', () => {
      playPlaylist(MOCK_ARTICLES);
    });
  }

  // ==================== LANGUAGE CONTROLLER ====================
  function setLanguage(lang) {
    currentLanguage = lang;
    
    langOptions.forEach(opt => {
      opt.classList.remove('active');
      if (opt.getAttribute('data-lang') === currentLanguage) {
        opt.classList.add('active');
      }
    });

    translateUIChrome();
    
    // Also sync the settings checks in the menu if menu is loaded
    if (typeof syncMenuSettingsUI === 'function') {
      syncMenuSettingsUI();
    }
  }

  function setupLanguage() {
    langToggleBtn.addEventListener('click', () => {
      const nextLang = currentLanguage === 'en' ? 'te' : 'en';
      setLanguage(nextLang);
    });
  }

  // ==================== SEARCH ENGINE ====================
  function setupSearch() {
    searchInput.addEventListener('input', () => {
      const query = searchInput.value.trim().toLowerCase();
      if (query) {
        clearSearchBtn.style.display = 'block';
        searchSuggestions.style.display = 'none';
        searchResultsList.style.display = 'flex';
        performSearch(query);
      } else {
        clearSearchBtn.style.display = 'none';
        searchSuggestions.style.display = 'block';
        searchResultsList.style.display = 'none';
      }
    });

    clearSearchBtn.addEventListener('click', () => {
      searchInput.value = '';
      clearSearchBtn.style.display = 'none';
      searchSuggestions.style.display = 'block';
      searchResultsList.style.display = 'none';
    });

    // Clicking category suggest tiles pre-fills query
    suggestionTiles.forEach(tile => {
      tile.addEventListener('click', () => {
        const cat = tile.getAttribute('data-category');
        searchInput.value = cat;
        searchInput.dispatchEvent(new Event('input'));
      });
    });
  }

  function renderSearchSuggestions() {
    // Translate text in suggestion tiles
    suggestionTiles.forEach(tile => {
      const cat = tile.getAttribute('data-category');
      const labelEl = tile.querySelector('.label');
      const subEl = tile.querySelector('.sub');
      labelEl.textContent = sectionLabel(cat);
      subEl.textContent = cat;
    });
  }

  function performSearch(query) {
    searchResultsList.innerHTML = '';
    const results = MOCK_ARTICLES.filter(a => 
      a.title.toLowerCase().includes(query) || 
      a.content.toLowerCase().includes(query) ||
      a.category.toLowerCase().includes(query)
    );

    if (results.length === 0) {
      searchResultsList.innerHTML = `
        <div style="text-align:center; padding:40px 0; color:var(--text-secondary); font-size:13px;">
          No articles found for "${query}"
        </div>
      `;
      return;
    }

    results.forEach(article => {
      const card = document.createElement('div');
      card.className = 'article-card';
      card.setAttribute('data-article-id', article.id);
      card.innerHTML = `
        <div class="article-card-left">
          <span class="category-tag">${sectionLabel(article.category)} • P${article.page}</span>
          <h4 class="headline">${article.title}</h4>
          <p class="snippet">${article.preview}</p>
        </div>
        <div class="article-card-play-btn">
          <svg viewBox="0 0 24 24"><path fill="currentColor" d="M8 5v14l11-7z"/></svg>
        </div>
      `;
      card.addEventListener('click', (e) => {
        const isCurrent = currentPlayingArticle && currentPlayingArticle.id === article.id;
        if (isCurrent && e.target.closest('.article-card-play-btn')) {
          togglePlayback();
        } else {
          playArticle(article);
        }
      });
      searchResultsList.appendChild(card);
    });

    syncArticlePlayingStates();
  }

  // ==================== LIBRARY CONTROLLER ====================
  function setupLibrary() {
    clearHistoryBtn.addEventListener('click', () => {
      historyList = [];
      localStorage.setItem('antigravity_history', JSON.stringify(historyList));
      renderLibraryHistory();
    });
  }

  function renderLibraryHistory() {
    libraryHistoryList.innerHTML = '';
    if (historyList.length === 0) {
      libraryHistoryList.innerHTML = `
        <div style="text-align:center; padding:40px 0; color:var(--text-secondary); font-size:13px;">
          No listening history yet.
        </div>
      `;
      return;
    }

    // Map history elements back to articles
    historyList.forEach(hist => {
      const article = MOCK_ARTICLES.find(a => a.id === hist.id);
      if (!article) return;

      const dateObj = new Date(hist.playedAt);
      const timeStr = dateObj.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

      const card = document.createElement('div');
      card.className = 'article-card';
      card.setAttribute('data-article-id', article.id);
      card.innerHTML = `
        <div class="article-card-left">
          <span class="category-tag">${sectionLabel(article.category)} • Played at ${timeStr}</span>
          <h4 class="headline">${article.title}</h4>
        </div>
        <div class="article-card-play-btn">
          <svg viewBox="0 0 24 24"><path fill="currentColor" d="M8 5v14l11-7z"/></svg>
        </div>
      `;
      card.addEventListener('click', (e) => {
        const isCurrent = currentPlayingArticle && currentPlayingArticle.id === article.id;
        if (isCurrent && e.target.closest('.article-card-play-btn')) {
          togglePlayback();
        } else {
          playArticle(article);
        }
      });
      libraryHistoryList.appendChild(card);
    });

    syncArticlePlayingStates();
  }

  function addToHistory(articleId) {
    // Keep list unique and capped to latest 10 items
    historyList = historyList.filter(h => h.id !== articleId);
    historyList.unshift({
      id: articleId,
      playedAt: new Date().toISOString()
    });
    historyList = historyList.slice(0, 10);
    localStorage.setItem('antigravity_history', JSON.stringify(historyList));
  }

  // ==================== PLAYBACK AUDIO ENGINE (SIMULATED) ====================
  function setupPlayback() {
    // Toggle play/pause from mini-player
    miniPlayerToggle.addEventListener('click', (e) => {
      e.stopPropagation(); // Don't expand player
      togglePlayback();
    });

    // Clicking mini-player expands to fullscreen
    miniPlayer.addEventListener('click', (e) => {
      if (!e.target.closest('.player-controls')) {
        expandLyricsPlayer();
      }
    });

    closePlayerBtn.addEventListener('click', collapseLyricsPlayer);
    closePlayerBtn.addEventListener('touchstart', collapseLyricsPlayer, { passive: true });

    // Full Player controls
    fullPlayerToggle.addEventListener('click', togglePlayback);
    progressSlider.addEventListener('input', handleSliderChange);
    
    playerSpeedBtn.addEventListener('click', () => {
      const speeds = [1.0, 1.25, 1.5, 2.0, 0.75];
      let idx = speeds.indexOf(playbackSpeed);
      playbackSpeed = speeds[(idx + 1) % speeds.length];
      playerSpeedBtn.textContent = `${playbackSpeed}x`;
    });

    toggleFavoriteBtn.addEventListener('click', () => {
      if (!currentPlayingArticle) return;
      const id = currentPlayingArticle.id;
      const isFav = favoritesList.includes(id);
      
      if (isFav) {
        favoritesList = favoritesList.filter(fId => fId !== id);
        favIcon.style.display = 'none';
        unfavIcon.style.display = 'block';
      } else {
        favoritesList.push(id);
        favIcon.style.display = 'block';
        unfavIcon.style.display = 'none';
      }
      localStorage.setItem('antigravity_favorites', JSON.stringify(favoritesList));
    });

    // Next/Prev controls
    miniPlayerPrev.addEventListener('click', (e) => { e.stopPropagation(); playPrevArticle(); });
    miniPlayerNext.addEventListener('click', (e) => { e.stopPropagation(); playNextArticle(); });
    fullPlayerPrev.addEventListener('click', playPrevArticle);
    fullPlayerNext.addEventListener('click', playNextArticle);
  }

  function playArticle(article) {
    currentPlayingArticle = article;
    addToHistory(article.id);
    
    isPlaying = true;
    playTimeElapsed = 0;
    activeSentenceIndex = 0;
    
    miniPlayer.style.display = 'block';
    
    // Sync buttons
    showPauseIcon();
    updateMiniPlayerUI();
    updateFullPlayerUI();
    renderLyrics();
    
    speakCurrentSentence();
    startPlaybackTimer();
    
    // Sync UI states for list cards
    syncArticlePlayingStates();
  }

  let playlistQueue = [];
  let playlistIndex = 0;

  function playPlaylist(list) {
    if (list.length === 0) return;
    playlistQueue = list;
    playlistIndex = 0;
    playArticle(playlistQueue[playlistIndex]);
  }

  function playNextArticle() {
    if (playlistQueue.length > 0 && playlistIndex < playlistQueue.length - 1) {
      playlistIndex++;
      playArticle(playlistQueue[playlistIndex]);
    } else {
      // Just wrap around main list if playing single
      const currentIdx = MOCK_ARTICLES.findIndex(a => a.id === currentPlayingArticle.id);
      const nextIdx = (currentIdx + 1) % MOCK_ARTICLES.length;
      playArticle(MOCK_ARTICLES[nextIdx]);
    }
  }

  function playPrevArticle() {
    if (playlistQueue.length > 0 && playlistIndex > 0) {
      playlistIndex--;
      playArticle(playlistQueue[playlistIndex]);
    } else {
      const currentIdx = MOCK_ARTICLES.findIndex(a => a.id === currentPlayingArticle.id);
      let prevIdx = currentIdx - 1;
      if (prevIdx < 0) prevIdx = MOCK_ARTICLES.length - 1;
      playArticle(MOCK_ARTICLES[prevIdx]);
    }
  }

  function togglePlayback() {
    if (!currentPlayingArticle) return;
    isPlaying = !isPlaying;
    
    if (isPlaying) {
      showPauseIcon();
      speakCurrentSentence();
      startPlaybackTimer();
    } else {
      showPlayIcon();
      clearInterval(playbackTimer);
      window.speechSynthesis.cancel();
    }

    // Sync UI states for list cards
    syncArticlePlayingStates();
  }

  let sentenceDuration = 0;
  let showedTeluguVoiceWarning = false;

  function showSystemVoiceWarning() {
    const toast = document.createElement('div');
    toast.style.position = 'fixed';
    toast.style.bottom = '100px';
    toast.style.left = '50%';
    toast.style.transform = 'translateX(-50%) translateY(20px)';
    toast.style.backgroundColor = 'rgba(255, 152, 0, 0.95)';
    toast.style.color = '#fff';
    toast.style.padding = '12px 20px';
    toast.style.borderRadius = '12px';
    toast.style.boxShadow = '0 8px 32px rgba(0, 0, 0, 0.3)';
    toast.style.fontSize = '12px';
    toast.style.fontWeight = '500';
    toast.style.zIndex = '9999';
    toast.style.transition = 'all 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275)';
    toast.style.opacity = '0';
    toast.style.textAlign = 'center';
    toast.style.maxWidth = '320px';
    toast.style.backdropFilter = 'blur(8px)';
    toast.style.border = '1px solid rgba(255, 255, 255, 0.2)';
    
    toast.innerHTML = `
      <div style="font-weight: 700; margin-bottom: 4px;">⚠️ Telugu Voice Not Installed</div>
      <div style="opacity: 0.9;">Playing audio with system default voice. Go to system settings to download a Telugu TTS voice.</div>
    `;
    
    document.body.appendChild(toast);
    
    setTimeout(() => {
      toast.style.opacity = '1';
      toast.style.transform = 'translateX(-50%) translateY(0)';
    }, 50);
    
    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateX(-50%) translateY(-20px)';
      setTimeout(() => {
        toast.remove();
      }, 400);
    }, 6000);
  }

  function speakCurrentSentence() {
    window.speechSynthesis.cancel();
    
    if (!currentPlayingArticle || !isPlaying) return;
    
    const count = currentPlayingArticle.sentences.length;
    if (activeSentenceIndex >= count) {
      playNextArticle();
      return;
    }
    
    const text = currentPlayingArticle.sentences[activeSentenceIndex];
    const utterance = new SpeechSynthesisUtterance(text);
    
    // Select voice
    const voices = window.speechSynthesis.getVoices();
    const teluguVoice = voices.find(v => v.lang.startsWith('te') || v.lang.includes('Telugu'));
    if (teluguVoice) {
      utterance.voice = teluguVoice;
      utterance.lang = 'te-IN';
    } else {
      console.warn("No Telugu voice found. Falling back to default system voice.");
      if (!showedTeluguVoiceWarning) {
        showedTeluguVoiceWarning = true;
        showSystemVoiceWarning();
      }
    }
    
    utterance.rate = playbackSpeed;
    
    // Set time elapsed at start of sentence
    sentenceDuration = currentPlayingArticle.duration / count;
    playTimeElapsed = activeSentenceIndex * sentenceDuration;
    updateProgressUI();
    
    utterance.onend = () => {
      if (isPlaying && currentPlayingArticle) {
        activeSentenceIndex++;
        if (activeSentenceIndex < count) {
          highlightActiveLyric();
          speakCurrentSentence();
        } else {
          // Article finished
          playTimeElapsed = currentPlayingArticle.duration;
          updateProgressUI();
          playNextArticle();
        }
      }
    };
    
    utterance.onerror = (e) => {
      console.warn("SpeechSynthesisUtterance error or cancelled:", e);
    };
    
    // Chrome workaround for rapid cancel/speak calls
    setTimeout(() => {
      if (isPlaying && currentPlayingArticle) {
        window.speechSynthesis.speak(utterance);
      }
    }, 100);
  }

  function startPlaybackTimer() {
    clearInterval(playbackTimer);
    playbackTimer = setInterval(() => {
      if (!isPlaying || !currentPlayingArticle) return;
      
      const count = currentPlayingArticle.sentences.length;
      const sentenceDur = currentPlayingArticle.duration / count;
      
      playTimeElapsed += 1 * playbackSpeed;
      
      // Cap elapsed time so it doesn't overflow into the next sentence's time range prematurely
      const maxElapsed = (activeSentenceIndex + 0.95) * sentenceDur;
      if (playTimeElapsed > maxElapsed) {
        playTimeElapsed = maxElapsed;
      }
      
      updateProgressUI();
    }, 1000);
  }

  function syncArticlePlayingStates() {
    const cards = document.querySelectorAll('.article-card');
    cards.forEach(card => {
      const articleId = card.getAttribute('data-article-id');
      const isCurrent = currentPlayingArticle && currentPlayingArticle.id === articleId;
      const playBtn = card.querySelector('.article-card-play-btn');
      
      if (isCurrent) {
        card.classList.add('playing');
        if (isPlaying) {
          card.classList.add('active-play');
          if (playBtn) {
            playBtn.classList.add('active');
            playBtn.innerHTML = `
              <div class="playing-equalizer">
                <span class="bar bar-1"></span>
                <span class="bar bar-2"></span>
                <span class="bar bar-3"></span>
              </div>
            `;
          }
        } else {
          card.classList.remove('active-play');
          if (playBtn) {
            playBtn.classList.add('active');
            playBtn.innerHTML = `<svg viewBox="0 0 24 24"><path fill="currentColor" d="M8 5v14l11-7z"/></svg>`;
          }
        }
      } else {
        card.classList.remove('playing', 'active-play');
        if (playBtn) {
          playBtn.classList.remove('active');
          playBtn.innerHTML = `<svg viewBox="0 0 24 24"><path fill="currentColor" d="M8 5v14l11-7z"/></svg>`;
        }
      }
    });
  }

  function updateProgressUI() {
    if (!currentPlayingArticle) return;
    
    const duration = currentPlayingArticle.duration;
    const progressPct = (playTimeElapsed / duration) * 100;
    
    // Update Slider & Fills
    miniPlayerProgress.style.width = `${progressPct}%`;
    progressSlider.value = progressPct;
    
    // Update elapsed labels
    playerTimeElapsed.textContent = formatTime(playTimeElapsed);
  }

  function handleSliderChange() {
    if (!currentPlayingArticle) return;
    const pct = progressSlider.value;
    playTimeElapsed = (pct / 100) * currentPlayingArticle.duration;
    
    // Jump to the corresponding sentence
    const count = currentPlayingArticle.sentences.length;
    activeSentenceIndex = Math.floor((pct / 100) * count);
    if (activeSentenceIndex >= count) activeSentenceIndex = count - 1;
    
    highlightActiveLyric();
    updateProgressUI();

    if (isPlaying) {
      speakCurrentSentence();
    }
  }

  function formatTime(secs) {
    const m = Math.floor(secs / 60);
    const s = Math.floor(secs % 60);
    return `${m}:${s < 10 ? '0' : ''}${s}`;
  }

  function showPauseIcon() {
    miniPlayerToggle.querySelector('.play-icon').style.display = 'none';
    miniPlayerToggle.querySelector('.pause-icon').style.display = 'block';
    fullPlayerToggle.querySelector('.play-icon').style.display = 'none';
    fullPlayerToggle.querySelector('.pause-icon').style.display = 'block';
  }

  function showPlayIcon() {
    miniPlayerToggle.querySelector('.play-icon').style.display = 'block';
    miniPlayerToggle.querySelector('.pause-icon').style.display = 'none';
    fullPlayerToggle.querySelector('.play-icon').style.display = 'block';
    fullPlayerToggle.querySelector('.pause-icon').style.display = 'none';
  }

  function updateMiniPlayerUI() {
    if (!currentPlayingArticle) return;
    miniPlayerTitle.textContent = currentPlayingArticle.title;
    miniPlayerSubtitle.textContent = sectionLabel(currentPlayingArticle.category);
  }

  function updateFullPlayerUI() {
    if (!currentPlayingArticle) return;
    playerTimeTotal.textContent = formatTime(currentPlayingArticle.duration);
    
    // Suggested speaker
    speakerNameText.textContent = currentPlayingArticle.speaker;
    
    // Favorite icon toggle
    const isFav = favoritesList.includes(currentPlayingArticle.id);
    if (isFav) {
      favIcon.style.display = 'block';
      unfavIcon.style.display = 'none';
    } else {
      favIcon.style.display = 'none';
      unfavIcon.style.display = 'block';
    }
  }

  // ==================== LYRICS RENDERER & SYNC ====================
  function renderLyrics() {
    lyricsLinesContainer.innerHTML = '';
    if (!currentPlayingArticle) return;
    
    currentPlayingArticle.sentences.forEach((sentence, idx) => {
      const line = document.createElement('div');
      line.className = 'lyrics-line';
      if (idx === activeSentenceIndex) line.classList.add('active');
      line.textContent = sentence;
      
      // Clicking a sentence seeks the player directly to it!
      line.addEventListener('click', () => {
        const count = currentPlayingArticle.sentences.length;
        const targetPct = idx / count;
        playTimeElapsed = targetPct * currentPlayingArticle.duration;
        activeSentenceIndex = idx;
        
        highlightActiveLyric();
        updateProgressUI();

        if (isPlaying) {
          speakCurrentSentence();
        }
      });

      lyricsLinesContainer.appendChild(line);
    });

    setTimeout(scrollLyricToCenter, 100);
  }

  function highlightActiveLyric() {
    const lines = lyricsLinesContainer.querySelectorAll('.lyrics-line');
    lines.forEach((line, idx) => {
      line.classList.remove('active');
      if (idx === activeSentenceIndex) {
        line.classList.add('active');
      }
    });
    scrollLyricToCenter();
  }

  function scrollLyricToCenter() {
    const activeLine = lyricsLinesContainer.querySelector('.lyrics-line.active');
    if (activeLine) {
      const containerHeight = lyricsLinesContainer.clientHeight;
      const lineTop = activeLine.offsetTop;
      const lineHeight = activeLine.clientHeight;
      
      // Calculate scroll position to center the line
      const targetScrollTop = lineTop - (containerHeight / 2) + (lineHeight / 2);
      
      lyricsLinesContainer.scrollTo({
        top: targetScrollTop,
        behavior: 'smooth'
      });
    }
  }

  function expandLyricsPlayer() {
    // Reset any viewport/container scroll offsets
    window.scrollTo(0, 0);
    document.body.scrollTop = 0;
    document.documentElement.scrollTop = 0;
    const appContainer = document.querySelector('.app-container');
    if (appContainer) appContainer.scrollTop = 0;

    lyricsPlayer.classList.add('active');
    setTimeout(scrollLyricToCenter, 300);
  }

  function collapseLyricsPlayer(e) {
    if (e) {
      e.stopPropagation();
      e.preventDefault();
    }
    lyricsPlayer.classList.remove('active');
    
    // Reset any viewport/container scroll offsets to guarantee alignment
    window.scrollTo(0, 0);
    document.body.scrollTop = 0;
    document.documentElement.scrollTop = 0;
    const appContainer = document.querySelector('.app-container');
    if (appContainer) appContainer.scrollTop = 0;
  }

  // ==================== SIMULATED UPLOAD & PROCESSING FLOW ====================
  function setupUpload() {
    uploadTrigger.addEventListener('click', () => {
      uploadModal.style.display = 'flex';
      resetUploadModal();
    });

    closeUploadModal.addEventListener('click', () => {
      uploadModal.style.display = 'none';
    });

    fileDropZone.addEventListener('click', () => {
      realFileInput.click();
    });

    realFileInput.addEventListener('change', () => {
      if (realFileInput.files.length > 0) {
        const file = realFileInput.files[0];
        showSelectedFile(file.name);
      }
    });

    // Drag-over styling
    fileDropZone.addEventListener('dragover', (e) => {
      e.preventDefault();
      fileDropZone.style.borderColor = 'var(--accent)';
      fileDropZone.style.background = 'rgba(240, 109, 59, 0.05)';
    });

    fileDropZone.addEventListener('dragleave', () => {
      fileDropZone.style.borderColor = 'var(--line-border)';
      fileDropZone.style.background = 'rgba(255, 255, 255, 0.01)';
    });

    fileDropZone.addEventListener('drop', (e) => {
      e.preventDefault();
      fileDropZone.style.borderColor = 'var(--line-border)';
      fileDropZone.style.background = 'rgba(255, 255, 255, 0.01)';
      if (e.dataTransfer.files.length > 0) {
        const file = e.dataTransfer.files[0];
        showSelectedFile(file.name);
      }
    });

    startProcessBtn.addEventListener('click', startSimulatedProcessing);
  }

  function resetUploadModal() {
    fileDropZone.style.display = 'flex';
    uploadProgressContainer.style.display = 'none';
    startProcessBtn.disabled = true;
    startProcessBtn.textContent = tr('Start Processing');
    realFileInput.value = '';
    
    // Zone reset
    fileDropZone.querySelector('.zone-text').textContent = tr('Drag & drop file here or click to browse');
    fileDropZone.querySelector('.zone-icon').style.color = 'var(--text-secondary)';
  }

  function showSelectedFile(name) {
    fileDropZone.querySelector('.zone-text').innerHTML = `Selected: <strong style="color:var(--accent);">${name}</strong>`;
    fileDropZone.querySelector('.zone-icon').style.color = 'var(--accent)';
    startProcessBtn.disabled = false;
  }

  function startSimulatedProcessing() {
    fileDropZone.style.display = 'none';
    uploadProgressContainer.style.display = 'block';
    startProcessBtn.disabled = true;
    
    let progress = 0;
    const interval = setInterval(() => {
      progress += 5;
      uploadProgressPercent.textContent = `${progress}%`;
      uploadProgressInner.style.width = `${progress}%`;
      
      if (progress < 50) {
        uploadProgressText.textContent = `Uploading document...`;
      } else if (progress < 95) {
        uploadProgressText.textContent = `Segmenting columns & running OCR...`;
      } else {
        uploadProgressText.textContent = `Synthesizing audio briefing...`;
      }

      if (progress >= 100) {
        clearInterval(interval);
        
        // Add new simulated article to data database
        const newArt = {
          id: `sim_${Date.now()}`,
          title: "హైదరాబాద్‌ లో మెట్రో రైలు విస్తరణ పనుల వేగవంతం",
          preview: "మెట్రో రెండో దశ విస్తరణ పనులను మూడు ఏళ్లలో పూర్తి చేయాలని ప్రభుత్వం లక్ష్యంగా పెట్టుకుంది.",
          content: "హైదరాబాద్ నగరాన్ని మరింత అనుసంధానించేందుకు మెట్రో రైల్ రెండో దశ విస్తరణ పనులను ప్రభుత్వం ప్రతిష్టాత్మకంగా చేపట్టింది. ఇందుకోసం బడ్జెట్‌లో ప్రత్యేక నిధులు కేటాయించినట్లు రవాణా శాఖ మంత్రి తెలిపారు. శంషాబాద్ విమానాశ్రయం మరియు గచ్చిబౌలి ఐటీ కారిడార్ మార్గాలకు ప్రాధాన్యత ఇస్తూ సర్వే పనులు ప్రారంభించారు. పనుల వేగవంతానికి ప్రత్యేక కమిటీని ఏర్పాటు చేసారు.",
          category: "State",
          page: 1,
          duration: 95,
          speaker: "Priya",
          sentences: [
            "హైదరాబాద్‌ లో మెట్రో రైలు విస్తరణ పనుల వేగవంతం.",
            "మెట్రో రెండో దశ విస్తరణ పనులను వేగవంతం చేసేందుకు ప్రభుత్వం ప్రణాళికలు రచించింది.",
            "శంషాబాద్ విమానాశ్రయ కారిడార్ మార్గాలకు సర్వే పనులు మొదలయ్యాయి.",
            "ఈ పనులను రానున్న మూడు సంవత్సరాలలో పూర్తి చేయడమే లక్ష్యంగా పెట్టుకున్నారు.",
            "మౌలిక సదుపాయాల బలోపేతానికి ఈ ప్రాజెక్ట్ చాలా కీలకమని అధికారులు పేర్కొన్నారు."
          ]
        };
        
        MOCK_ARTICLES.unshift(newArt);
        
        // Refresh home UI
        renderRecentMarquee();
        if (activeLayoutView === 'tiles') {
          renderMainGrid();
        } else {
          renderMainList();
        }

        // Close modal and play the new article!
        setTimeout(() => {
          uploadModal.style.display = 'none';
          playArticle(newArt);
        }, 800);
      }
    }, 200);
  }

  function setupMenu() {
    menuTriggerBtn.addEventListener('click', () => {
      menuDrawer.classList.add('active');
      syncMenuSettingsUI();
    });
    
    closeMenuBtn.addEventListener('click', () => {
      menuDrawer.classList.remove('active');
    });
    
    closeMenuBtn.addEventListener('touchstart', (e) => {
      e.stopPropagation();
      e.preventDefault();
      menuDrawer.classList.remove('active');
    }, { passive: false });
    
    // Language clicks
    optLangEn.addEventListener('click', () => setLanguage('en'));
    optLangTe.addEventListener('click', () => setLanguage('te'));
    
    // Theme clicks
    optThemeDark.addEventListener('click', () => setTheme('dark'));
    optThemeLight.addEventListener('click', () => setTheme('light'));
    
    // Playback Speed clicks
    menuSpeedOptions.querySelectorAll('.settings-row').forEach(row => {
      row.addEventListener('click', () => {
        const speed = parseFloat(row.getAttribute('data-menu-speed'));
        playbackSpeed = speed;
        
        // Update player speed button label
        playerSpeedBtn.textContent = `${speed}x`;
        
        // If playing, restart speaking with the new speed
        if (isPlaying) {
          speakCurrentSentence();
        }
        
        syncMenuSettingsUI();
      });
    });
    
    // Sign-in / Sign-up mock simulation
    menuSignInBtn.addEventListener('click', () => simulateSignIn("Siddhartha"));
    menuSignUpBtn.addEventListener('click', () => simulateSignIn("Siddhartha"));
  }

  function setTheme(theme) {
    currentTheme = theme;
    const appContainer = document.querySelector('.app-container');
    if (theme === 'light') {
      appContainer.classList.add('light-mode');
    } else {
      appContainer.classList.remove('light-mode');
    }
    syncMenuSettingsUI();
  }

  function simulateSignIn(name) {
    menuProfileName.textContent = name;
    menuProfileName.setAttribute('data-en', name);
    menuProfileName.setAttribute('data-te', name);
    
    const subTextEn = "Member since June 2026";
    const subTextTe = "జూన్ 2026 నుండి సభ్యులు";
    menuProfileSub.textContent = currentLanguage === 'te' ? subTextTe : subTextEn;
    menuProfileSub.setAttribute('data-en', subTextEn);
    menuProfileSub.setAttribute('data-te', subTextTe);
    
    menuAccountActions.innerHTML = `
      <button class="account-btn secondary-btn" id="menu-signout-btn" data-en="Sign Out" data-te="లాగ్ అవుట్">Sign Out</button>
    `;
    
    translateUIChrome();
    
    document.getElementById('menu-signout-btn').addEventListener('click', () => {
      simulateSignOut();
    });
  }

  function simulateSignOut() {
    menuProfileName.textContent = currentLanguage === 'te' ? "అతిథి వినియోగదారు" : "Guest User";
    menuProfileName.setAttribute('data-en', "Guest User");
    menuProfileName.setAttribute('data-te', "అతిథి వినియోగదారు");
    
    menuProfileSub.textContent = currentLanguage === 'te' ? "మీ లైబ్రరీని సమకాలీకరించడానికి లాగిన్ అవ్వండి" : "Sign in to sync your library";
    menuProfileSub.setAttribute('data-en', "Sign in to sync your library");
    menuProfileSub.setAttribute('data-te', "మీ లైబ్రరీని సమకాలీకరించడానికి లాగిన్ అవ్వండి");
    
    menuAccountActions.innerHTML = `
      <button class="account-btn primary-btn" id="menu-signin-btn" data-en="Sign In" data-te="లాగ్‌ఇన్">Sign In</button>
      <button class="account-btn secondary-btn" id="menu-signup-btn" data-en="Sign Up" data-te="నమోదు చేసుకోండి">Sign Up</button>
    `;
    
    translateUIChrome();
    
    document.getElementById('menu-signin-btn').addEventListener('click', () => simulateSignIn("Siddhartha"));
    document.getElementById('menu-signup-btn').addEventListener('click', () => simulateSignIn("Siddhartha"));
  }

  function syncMenuSettingsUI() {
    // Language rows selected state
    const langEnRow = document.getElementById('opt-lang-en');
    const langTeRow = document.getElementById('opt-lang-te');
    langEnRow.classList.toggle('selected', currentLanguage === 'en');
    langTeRow.classList.toggle('selected', currentLanguage === 'te');
    
    // Theme rows selected state
    const themeDarkRow = document.getElementById('opt-theme-dark');
    const themeLightRow = document.getElementById('opt-theme-light');
    themeDarkRow.classList.toggle('selected', currentTheme === 'dark');
    themeLightRow.classList.toggle('selected', currentTheme === 'light');
    
    // Playback Speed rows selected state
    menuSpeedOptions.querySelectorAll('.settings-row').forEach(row => {
      const speed = parseFloat(row.getAttribute('data-menu-speed'));
      row.classList.toggle('selected', playbackSpeed === speed);
    });
  }

  // Execute App Initialization
  init();
});
