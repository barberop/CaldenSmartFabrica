import 'dart:convert';

import 'package:caldensmartfabrica/aws/dynamo/dynamo.dart';
import 'package:caldensmartfabrica/aws/mqtt/mqtt.dart';
import 'package:flutter/material.dart';

import '../../master.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});
  @override
  ToolsPageState createState() => ToolsPageState();
}

class ToolsPageState extends State<ToolsPage> {
  TextEditingController textController = TextEditingController();

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  void sendDataToDevice() async {
    String dataToSend = textController.text;
    String data = '${DeviceManager.getProductCode(deviceName)}[4]($dataToSend)';
    try {
      await myDevice.toolsUuid.write(data.codeUnits);
    } catch (e) {
      printLog(e);
    }
  }

  void _finalizeProcess() async {
    final pc = DeviceManager.getProductCode(deviceName);
    final sn = DeviceManager.extractSerialNumber(deviceName);
    registerActivity(
      pc,
      sn,
      'Se finalizó el proceso de laboratorio',
    );

    final msg = jsonEncode({'LabFinished': true});

    final topic1 = 'devices_rx/$pc/$sn';
    final topic2 = 'devices_tx/$pc/$sn';

    sendMessagemqtt(topic1, msg);
    sendMessagemqtt(topic2, msg);

    if (pc == '022000_IOT' || pc == '027000_IOT' || pc == '041220_IOT') {
      myDevice.toolsUuid.write('$pc[7](10)'.codeUnits);
    }

    await putLabProcessFinished(pc, sn, true);
    showToast('Proceso de laboratorio finalizado correctamente.');
  }

  //! Visual
  @override
  Widget build(BuildContext context) {
    double bottomBarHeight = kBottomNavigationBarHeight;
    return SingleChildScrollView(
      child: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text.rich(
              TextSpan(
                text: 'Número de serie',
                style: TextStyle(
                  fontSize: 30.0,
                  color: color1,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text.rich(
              TextSpan(
                text: DeviceManager.extractSerialNumber(deviceName),
                style: const TextStyle(
                  fontSize: 30.0,
                  color: color0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (accessLevel > 1) ...{
              const SizedBox(height: 10),
              buildTextField(
                controller: textController,
                label: 'Introducir nuevo numero de serie',
                hint: 'Nuevo número de serie',
                onSubmitted: (text) {},
                widthFactor: 0.8,
                keyboard: TextInputType.number,
              ),
              buildButton(
                text: 'Enviar',
                onPressed: () {
                  registerActivity(
                    DeviceManager.getProductCode(deviceName),
                    textController.text,
                    'Se coloco el número de serie',
                  );
                  sendDataToDevice();
                },
              ),
            },
            const SizedBox(height: 10),
            buildText(
              text:
                  'Código de producto: ${DeviceManager.getProductCode(deviceName)}',
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
              widthFactor: 0.8,
            ),
            buildText(
              text: 'Versión de software del módulo IOT: $softwareVersion',
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
              widthFactor: 0.8,
            ),
            buildText(
              text: 'Versión de hardware del módulo IOT: $hardwareVersion',
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
              widthFactor: 0.8,
            ),
            if (accessLevel > 1) ...{
              buildButton(
                text: 'Borrar NVS',
                onPressed: () {
                  registerActivity(
                    DeviceManager.getProductCode(deviceName),
                    DeviceManager.extractSerialNumber(deviceName),
                    'Se borró la NVS de este equipo...',
                  );
                  String data =
                      '${DeviceManager.getProductCode(deviceName)}[0](1)';
                  myDevice.toolsUuid.write(data.codeUnits);
                },
              ),
              const SizedBox(
                height: 20,
              ),
              buildButton(
                  text: 'Finalizar Proceso',
                  onPressed: () {
                    showAlertDialog(
                        context,
                        false,
                        const Text(
                          '¡ESTE BOTÓN DEBE SER PRESIONADO UNICAMENTE POR LABORATORIO!',
                          textAlign: TextAlign.center,
                        ),
                        const Text(
                            'Este botón marcará como finalizado el procedimiento de laboratorio.\nAl hacer esto, certificarás que el equipo cumplió todos sus pasos de manera correcta y sin fallos.\nEl mal uso o incumplimiento de este procedimiento causará una sanción a la persona correspondiente.\n'),
                        [
                          TextButton(
                            child: const Text('Cancelar'),
                            onPressed: () {
                              Navigator.pop(context);
                            },
                          ),
                          TextButton(
                            child: const Text('Aceptar'),
                            onPressed: () {
                              _finalizeProcess();
                              Navigator.pop(context);
                            },
                          ),
                        ]);
                  }),
            },
            const SizedBox(
              height: 20,
            ),
            Padding(
              padding: EdgeInsets.only(bottom: bottomBarHeight + 20),
            ),
          ],
        ),
      ),
    );
  }
}
