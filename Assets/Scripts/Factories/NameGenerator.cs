using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class NameGenerator : MonoBehaviour
{
  static List<string> names = new List<string>(new string[] { "Pedro", "Martín", "Federico", "Diego", "Christian", "Gabriel", "Nelson" });
  static List<string> surnames = new List<string>(new string[] {"Jara", "Marussi", "Galeano", "Volonnino", "Raffo", "Huberman", "Marcano"});
  static System.Random rnd = new System.Random();

  static public string getFullName(){
    string full_name = $"{names[rnd.Next(0,names.Count)]} {surnames[rnd.Next(0,surnames.Count)]}";
    Debug.Log(full_name);
    return full_name;
  }
}
