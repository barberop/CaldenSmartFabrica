import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:caldensmartfabrica/devices/globales/credentials.dart';
import 'package:caldensmartfabrica/devices/globales/ota.dart';
import 'package:caldensmartfabrica/devices/globales/params.dart';
import 'package:caldensmartfabrica/devices/globales/tools.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import '../aws/dynamo/dynamo.dart';
import '../master.dart';

class CalefactoresPage extends StatefulWidget {
  const CalefactoresPage({super.key});

  @override
  CalefactoresPageState createState() => CalefactoresPageState();
}

class CalefactoresPageState extends State<CalefactoresPage> {
  TextEditingController textController = TextEditingController();

  final TextEditingController roomTempController = TextEditingController();
  final TextEditingController distanceOnController =
      TextEditingController(text: distanceOn);
  final TextEditingController distanceOffController =
      TextEditingController(text: distanceOff);
  final PageController _pageController = PageController(initialPage: 0);
  int _selectedIndex = 0;
  bool ignite = false;
  bool recording = false;
  List<List<dynamic>> recordedData = [];
  Timer? recordTimer;

  void _onItemTapped(int index) {
    if ((index - _selectedIndex).abs() > 1) {
      _pageController.jumpToPage(index);
    } else {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    textController.dispose();
    roomTempController.dispose();
    distanceOnController.dispose();
    distanceOffController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    updateWifiValues(toolsValues);
    subscribeToWifiStatus();
    printLog('Valor temp: $tempValue');
    printLog('¿Encendido? $turnOn');
    subscribeTrueStatus();
  }

  void subscribeTrueStatus() async {
    printLog('Me subscribo a vars');
    await myDevice.varsUuid.setNotifyValue(true);

    final trueStatusSub =
        myDevice.varsUuid.onValueReceived.listen((List<int> status) {
      var parts = utf8.decode(status).split(':');
      printLog(parts);
      setState(() {
        trueStatus = parts[0] == '1';
        actualTemp = parts[1];
        if (parts.length > 2) {
          offsetTemp = parts[2];
        }
      });
    });

    myDevice.device.cancelWhenDisconnected(trueStatusSub);
  }

  void updateWifiValues(List<int> data) {
    var fun =
        utf8.decode(data); //Wifi status | wifi ssid | ble status | nickname
    fun = fun.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
    // printLog(fun);
    var parts = fun.split(':');
    if (parts[0] == 'WCS_CONNECTED') {
      nameOfWifi = parts[1];
      isWifiConnected = true;
      // printLog('sis $isWifiConnected');
      setState(() {
        textState = 'CONECTADO';
        statusColor = Colors.green;
        wifiIcon = Icons.wifi;
      });
    } else if (parts[0] == 'WCS_DISCONNECTED') {
      isWifiConnected = false;
      // printLog('non $isWifiConnected');

      setState(() {
        textState = 'DESCONECTADO';
        statusColor = Colors.red;
        wifiIcon = Icons.wifi_off;
      });

      if (parts[0] == 'WCS_DISCONNECTED' && atemp == true) {
        //If comes from subscription, parts[1] = reason of error.
        setState(() {
          wifiIcon = Icons.warning_amber_rounded;
          werror = true;
        });

        if (parts[1] == '202' || parts[1] == '15') {
          errorMessage = 'Contraseña incorrecta';
        } else if (parts[1] == '201') {
          errorMessage = 'La red especificada no existe';
        } else if (parts[1] == '1') {
          errorMessage = 'Error desconocido';
        } else {
          errorMessage = parts[1];
        }

        if (int.tryParse(parts[1]) != null) {
          errorSintax = getWifiErrorSintax(int.parse(parts[1]));
        }
      }
    }

    setState(() {});
  }

  void subscribeToWifiStatus() async {
    printLog('Se subscribio a wifi');
    await myDevice.toolsUuid.setNotifyValue(true);

    final wifiSub =
        myDevice.toolsUuid.onValueReceived.listen((List<int> status) {
      updateWifiValues(status);
    });

    myDevice.device.cancelWhenDisconnected(wifiSub);
  }

  void sendTemperature(int temp) {
    String data = '${DeviceManager.getProductCode(deviceName)}[7]($temp)';
    myDevice.toolsUuid.write(data.codeUnits);
  }

  void turnDeviceOn(bool on) {
    int fun = on ? 1 : 0;
    String data = '${DeviceManager.getProductCode(deviceName)}[11]($fun)';
    myDevice.toolsUuid.write(data.codeUnits);
  }

  void sendRoomTemperature(String temp) {
    String data = '${DeviceManager.getProductCode(deviceName)}[8]($temp)';
    myDevice.toolsUuid.write(data.codeUnits);
  }

  void startTempMap() {
    String data = '${DeviceManager.getProductCode(deviceName)}[12](0)';
    myDevice.toolsUuid.write(data.codeUnits);
  }

  void saveDataToCsv() async {
    List<List<dynamic>> rows = [
      [
        "Timestamp",
        "Temperatura",
        "Offset",
      ]
    ];
    rows.addAll(recordedData);

    String csvData = const ListToCsvConverter().convert(rows);
    final directory = await getApplicationDocumentsDirectory();
    final pathOfTheFileToWrite = '${directory.path}/temp_data.csv';
    File file = File(pathOfTheFileToWrite);
    await file.writeAsString(csvData);

    await Share.shareXFiles([XFile(file.path)], text: 'CSV TEMPERATURA');
  }

  //! VISUAL
  @override
  Widget build(BuildContext context) {
    double bottomBarHeight = kBottomNavigationBarHeight;
    final String pc = DeviceManager.getProductCode(deviceName);
    final String sn = DeviceManager.extractSerialNumber(deviceName);

    final List<Widget> pages = [
      //*- Página 1 TOOLS -*\\
      const ToolsPage(),
      if (accessLevel > 1) ...[
        //*- Página 2 PARAMS -*\\
        const ParamsTab(),
      ],

      //*- Página 3 CONTROL -*\\
      Scaffold(
        backgroundColor: color4,
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text.rich(
                  TextSpan(
                    text: turnOn
                        ? trueStatus
                            ? 'Calentando'
                            : 'Encendido'
                        : 'Apagado',
                    style: TextStyle(
                        color: turnOn
                            ? trueStatus
                                ? Colors.amber[600]
                                : Colors.green
                            : Colors.red,
                        fontSize: 30),
                  ),
                ),
                const SizedBox(height: 30),
                Transform.scale(
                  scale: 3.0,
                  child: Switch(
                    activeColor: color4,
                    activeTrackColor: color1,
                    inactiveThumbColor: color1,
                    inactiveTrackColor: color4,
                    value: turnOn,
                    onChanged: (value) {
                      turnDeviceOn(value);
                      setState(() {
                        turnOn = value;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 50),
                buildText(
                    text:
                        'Temperatura de corte: ${tempValue.round().toString()} °C'),
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.8,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 50.0,
                      valueIndicatorColor: color4,
                      thumbColor: color1,
                      activeTrackColor: color0,
                      inactiveTrackColor: color3,
                      thumbShape: IconThumbSlider(
                        iconData: trueStatus
                            ? pc == '027000_IOT'
                                ? Icons.local_fire_department
                                : Icons.flash_on_rounded
                            : Icons.check,
                        thumbRadius: 28,
                      ),
                    ),
                    child: Slider(
                      value: tempValue,
                      onChanged: (value) {
                        setState(() {
                          tempValue = value;
                        });
                      },
                      onChangeEnd: (value) {
                        printLog(value);
                        sendTemperature(value.round());
                      },
                      min: 0,
                      max: 40,
                    ),
                  ),
                ),
                if (pc == '027000_IOT') ...[
                  const SizedBox(
                    height: 30,
                  ),
                  GestureDetector(
                    onLongPressStart: (LongPressStartDetails a) async {
                      setState(() {
                        ignite = true;
                      });
                      while (ignite) {
                        await Future.delayed(const Duration(milliseconds: 500));
                        if (!ignite) break;
                        String data = '027000_IOT[15](1)';
                        myDevice.toolsUuid.write(data.codeUnits);
                        printLog(data);
                      }
                    },
                    onLongPressEnd: (LongPressEndDetails a) {
                      setState(() {
                        ignite = false;
                      });
                      String data = '027000_IOT[15](0)';
                      myDevice.toolsUuid.write(data.codeUnits);
                      printLog(data);
                    },
                    child: buildButton(onPressed: () {}, text: 'Chispero'),
                  ),
                  const SizedBox(
                    height: 30,
                  ),
                  buildText(text: '¿Este equipo tendrá chispero?'),
                  const SizedBox(
                    height: 10,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ChoiceChip(
                        label: const Text('SI tendrá chispero'),
                        selected: hasSpark,
                        onSelected: (sel) async {
                          setState(() => hasSpark = true);
                          await putHasSpark(pc, sn, true);
                          registerActivity(pc, sn,
                              "Se selecciono que el equipo posee chispero");
                        },
                        selectedColor: color1,
                        backgroundColor: color0,
                        labelStyle:
                            TextStyle(color: hasSpark ? color4 : color1),
                        checkmarkColor: color4,
                      ),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('NO tendrá chispero'),
                        selected: !hasSpark,
                        onSelected: (sel) async {
                          setState(() => hasSpark = false);
                          await putHasSpark(pc, sn, false);
                          registerActivity(pc, sn,
                              "Se selecciono que el equipo NO posee un chispero");
                        },
                        selectedColor: color1,
                        backgroundColor: color0,
                        labelStyle:
                            TextStyle(color: !hasSpark ? color4 : color1),
                        checkmarkColor: color4,
                      ),
                    ],
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                ],
                if (!hasSensor) ...[
                  const SizedBox(height: 30),
                  SizedBox(
                    width: 300,
                    child: !roomTempSended
                        ? buildTextField(
                            controller: roomTempController,
                            label: 'Introducir temperatura de la habitación',
                            hint: '',
                            keyboard: TextInputType.number,
                            onSubmitted: (value) {
                              registerActivity(pc, sn,
                                  'Se cambió la temperatura ambiente de $actualTemp°C a $value°C');
                              sendRoomTemperature(value);
                              registerTemp(
                                pc,
                                sn,
                              );
                              showToast('Temperatura ambiente seteada');
                              setState(() {
                                roomTempSended = true;
                              });
                            },
                          )
                        : buildText(
                            text: '',
                            textSpans: [
                              TextSpan(
                                text:
                                    'La temperatura ambiente ya fue seteada\npor este legajo el dia \n$tempDate',
                                style: const TextStyle(
                                    color: color4, fontWeight: FontWeight.bold),
                              ),
                            ],
                            fontSize: 20.0,
                            textAlign: TextAlign.center,
                          ),
                  ),
                ],
                const SizedBox(height: 30),
                buildText(
                  text: '',
                  textSpans: [
                    TextSpan(
                      text: 'Temperatura actual: $actualTemp °C',
                      style: const TextStyle(
                        color: color4,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  fontSize: 20.0,
                  textAlign: TextAlign.center,
                ),
                if (hasSensor) ...{
                  // const SizedBox(height: 10),
                  buildText(
                    text: '',
                    textSpans: [
                      TextSpan(
                        text: 'Offset temperatura: $offsetTemp °C',
                        style: const TextStyle(
                          color: color4,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    fontSize: 20.0,
                    textAlign: TextAlign.center,
                  ),
                  buildText(
                    text: '',
                    textSpans: [
                      TextSpan(
                        text:
                            'Lectura sensor: ${int.parse(actualTemp) + int.parse(offsetTemp)} °C',
                        style: const TextStyle(
                          color: color4,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    fontSize: 20.0,
                    textAlign: TextAlign.center,
                  ),
                },
                // const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      recording = !recording;
                    });
                    if (!recording) {
                      recordTimer?.cancel();
                      saveDataToCsv();
                      recordedData.clear();
                    } else {
                      recordTimer = Timer.periodic(
                        const Duration(seconds: 1),
                        (Timer t) {
                          if (recording) {
                            recordedData
                                .add([DateTime.now(), actualTemp, offsetTemp]);
                          }
                        },
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(20),
                    backgroundColor: color0,
                  ),
                  child: Icon(
                    recording ? Icons.pause : Icons.play_arrow,
                    size: 35,
                    color: color4,
                  ),
                ),
                const SizedBox(height: 20),
                if (factoryMode) ...[
                  if (!hasSensor) ...{
                    buildText(
                      text: '',
                      textSpans: [
                        const TextSpan(
                          text: 'Mapeo de temperatura:\n',
                          style: TextStyle(
                              color: color4, fontWeight: FontWeight.bold),
                        ),
                        TextSpan(
                          text: tempMap ? 'REALIZADO' : 'NO REALIZADO',
                          style: TextStyle(
                              color: tempMap
                                  ? Colors.green
                                  : const Color.fromARGB(255, 32, 21, 20),
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                      fontSize: 20.0,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    buildButton(
                      text: 'Iniciar mapeo temperatura',
                      onPressed: () {
                        registerActivity(pc, sn,
                            'Se inicio el mapeo de temperatura en el equipo');
                        startTempMap();
                        showToast('Iniciando mapeo de temperatura');
                      },
                    ),
                  },
                  if (pc == '027000_IOT') ...[
                    const SizedBox(
                      height: 10,
                    ),
                    buildButton(
                      text: 'Ciclado fijo',
                      onPressed: () {
                        registerActivity(pc, sn,
                            'Se mando el ciclado de la válvula de este equipo');
                        String data = '$pc[13](1000#5)';
                        myDevice.toolsUuid.write(data.codeUnits);
                      },
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    buildButton(
                      text: 'Configurar ciclado',
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            final TextEditingController cicleController =
                                TextEditingController();
                            final TextEditingController timeController =
                                TextEditingController();
                            return AlertDialog(
                              backgroundColor: color1,
                              title: const Center(
                                child: Text(
                                  'Especificar parametros del ciclador:',
                                  style: TextStyle(
                                    color: color4,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 300,
                                    child: TextField(
                                      style: const TextStyle(color: color4),
                                      controller: cicleController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Ingrese cantidad de ciclos',
                                        hintText: 'Certificación: 1000',
                                        labelStyle: TextStyle(color: color4),
                                        hintStyle: TextStyle(color: color4),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(
                                    height: 20,
                                  ),
                                  SizedBox(
                                    width: 300,
                                    child: TextField(
                                      style: const TextStyle(color: color4),
                                      controller: timeController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText:
                                            'Ingrese duración de los ciclos',
                                        hintText: 'Recomendado: 1000',
                                        suffixText: '(mS)',
                                        suffixStyle: TextStyle(
                                          color: color4,
                                        ),
                                        labelStyle: TextStyle(
                                          color: color4,
                                        ),
                                        hintStyle: TextStyle(
                                          color: color4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    navigatorKey.currentState!.pop();
                                  },
                                  child: const Text(
                                    'Cancelar',
                                    style: TextStyle(
                                      color: color4,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    int cicle =
                                        int.parse(cicleController.text) * 2;
                                    registerActivity(pc, sn,
                                        'Se mando el ciclado de la válvula de este equipo\nMilisegundos: ${timeController.text}\nIteraciones:$cicle');
                                    String data =
                                        '$pc[13](${timeController.text}#$cicle)';
                                    myDevice.toolsUuid.write(data.codeUnits);
                                    navigatorKey.currentState!.pop();
                                  },
                                  child: const Text(
                                    'Iniciar proceso',
                                    style: TextStyle(color: color4),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    buildButton(
                      text: 'Configurar Apertura\nTemporizada',
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            final TextEditingController timeController =
                                TextEditingController();
                            return AlertDialog(
                              title: const Center(
                                child: Text(
                                  'Especificar parametros de la apertura temporizada:',
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 300,
                                    child: TextField(
                                      style:
                                          const TextStyle(color: Colors.black),
                                      controller: timeController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText:
                                            'Ingrese cantidad de milisegundos',
                                        labelStyle:
                                            TextStyle(color: Colors.black),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    navigatorKey.currentState!.pop();
                                  },
                                  child: const Text('Cancelar'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    registerActivity(pc, sn,
                                        'Se mando el temporizado de apertura');
                                    String data =
                                        '$pc[14](${timeController.text.trim()})';
                                    myDevice.toolsUuid.write(data.codeUnits);
                                    navigatorKey.currentState!.pop();
                                  },
                                  child: const Text('Iniciar proceso'),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    )
                  ],
                  const SizedBox(
                    height: 20,
                  ),
                  buildText(
                    text: '',
                    textSpans: [
                      const TextSpan(
                        text: 'Distancias de control: ',
                        style: TextStyle(
                          color: color4,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    fontSize: 20.0,
                    textAlign: TextAlign.center,
                  ),
                  buildTextField(
                    controller: distanceOnController,
                    label: 'Distancia de encendido:',
                    hint: '',
                    keyboard: TextInputType.number,
                    onSubmitted: (value) {
                      if (int.parse(value) <= 5000 &&
                          int.parse(value) >= 3000) {
                        registerActivity(
                            pc, sn, 'Se modifico la distancia de encendido');
                        putDistanceOn(pc, sn, value);
                      } else {
                        showToast('Parametros no permitidos');
                      }
                    },
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  buildTextField(
                    controller: distanceOffController,
                    label: 'Distancia de apagado:',
                    hint: '',
                    keyboard: TextInputType.number,
                    onSubmitted: (value) {
                      if (int.parse(value) <= 300 && int.parse(value) >= 100) {
                        registerActivity(
                            pc, sn, 'Se modifico la distancia de apagado');
                        putDistanceOff(pc, sn, value);
                      } else {
                        showToast('Parametros no permitidos');
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  buildText(
                    text: '',
                    textSpans: [
                      const TextSpan(
                        text: 'Mono manual:',
                        style: TextStyle(
                          color: color4,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    fontSize: 20.0,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  buildButton(
                    text: manualControl ? 'Desactivar' : 'Activar',
                    onPressed: () {
                      registerActivity(
                        pc,
                        sn,
                        'Se activo el modo manual del equipo',
                      );
                      String data = '$pc[16](${manualControl ? '0' : '1'})';
                      myDevice.toolsUuid.write(data.codeUnits);
                      setState(() {
                        turnOn = false;
                        manualControl = !manualControl;
                      });
                    },
                  ),
                  const SizedBox(
                    height: 50,
                  ),
                ],
                Padding(
                  padding: EdgeInsets.only(bottom: bottomBarHeight + 20),
                ),
              ],
            ),
          ),
        ),
      ),

      if (accessLevel > 1) ...[
        //*- Página 4 CREDENTIAL -*\\
        const CredsTab(),
      ],

      //*- Página 5 OTA -*\\
      const OtaTab(),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, A) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              backgroundColor: color1,
              content: Row(
                children: [
                  Image.asset(
                      EasterEggs.legajosMeme.contains(legajoConectado)
                          ? 'assets/eg/DSC.gif'
                          : 'assets/Loading.gif',
                      width: 100,
                      height: 100),
                  Container(
                    margin: const EdgeInsets.only(left: 15),
                    child: const Text(
                      "Desconectando...",
                      style: TextStyle(color: color4),
                    ),
                  ),
                ],
              ),
            );
          },
        );
        Future.delayed(const Duration(seconds: 2), () async {
          await myDevice.device.disconnect();
          if (context.mounted) {
            Navigator.pop(context);
            Navigator.pushReplacementNamed(context, '/menu');
          }
        });
        return;
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: color1,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                deviceName,
                style: const TextStyle(
                  color: color4,
                ),
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new,
            ),
            color: color4,
            onPressed: () {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) {
                  return AlertDialog(
                    backgroundColor: color1,
                    content: Row(
                      children: [
                        Image.asset(
                            EasterEggs.legajosMeme.contains(legajoConectado)
                                ? 'assets/eg/DSC.gif'
                                : 'assets/Loading.gif',
                            width: 100,
                            height: 100),
                        Container(
                          margin: const EdgeInsets.only(left: 15),
                          child: const Text(
                            "Desconectando...",
                            style: TextStyle(
                              color: color4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
              Future.delayed(const Duration(seconds: 2), () async {
                await myDevice.device.disconnect();
                if (context.mounted) {
                  Navigator.pop(context);
                  Navigator.pushReplacementNamed(context, '/menu');
                }
              });
              return;
            },
          ),
          actions: [
            IconButton(
              icon: Icon(
                wifiIcon,
                color: color4,
              ),
              onPressed: () {
                wifiText(context);
              },
            ),
          ],
        ),
        backgroundColor: color4,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              children: pages,
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: CurvedNavigationBar(
                index: _selectedIndex,
                height: 75.0,
                items: <Widget>[
                  const Icon(Icons.settings, size: 30, color: color4),
                  if (accessLevel > 1) ...[
                    const Icon(Icons.star, size: 30, color: color4),
                  ],
                  const Icon(Icons.thermostat, size: 30, color: color4),
                  if (accessLevel > 1) ...[
                    const Icon(Icons.person, size: 30, color: color4),
                  ],
                  const Icon(Icons.send, size: 30, color: color4),
                ],
                color: color1,
                buttonBackgroundColor: color1,
                backgroundColor: Colors.transparent,
                animationCurve: Curves.easeInOut,
                animationDuration: const Duration(milliseconds: 600),
                onTap: (index) {
                  _onItemTapped(index);
                },
                letIndexChange: (index) => true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
