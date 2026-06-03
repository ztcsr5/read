void main() { 
  print("URI: >" + Uri.parse("https://test.com/").resolve(" ").toString() + "<"); 
}
