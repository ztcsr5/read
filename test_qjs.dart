import 'package:quickjs_engine/quickjs_engine.dart';
void main() {
  try {
    final runtime = getJavascriptRuntime();
    print("Runtime created");
    final res = runtime.evaluate('var a = 1; a + 1;');
    print("Eval result: \${res.stringResult}");
  } catch(e, s) {
    print("Error: \$e");
    print(s);
  }
}
