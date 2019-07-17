using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class NameGenerator : MonoBehaviour
{
  static List<string> names = new List<string>(new string[] { "Pedro", "Martín", "Federico", "Diego", "Christian", "Gabriel", "Luis Armando","Noodle","Batata","Sol Banner","Piba", "Justino",
                                                              "Elvis", "Pol", "El Cuki", "Pepito", "La Cucaracha", "El Papu", "Knott", "El Flor", "Pampa" , "Gonzalo", "Tini", "Pato", "Nelson"});
  static List<string> surnames = new List<string>(new string[] {"Jara", "Marussi", "Castolo", "Volonnino", "Parriaga", "Parriaga Segundo", "Teodoro", "Tijeras", "Gozalo", "Tinista" , "Macuca",
                                                                "Paredes","Su Marría", "Gutierrez","Cantina","Bifes", "Cocho","Macarne", "Sancrim", "Perinola", "Tute", "Cepe", "Podonga", "Mándela"});
  static System.Random rnd = new System.Random();

  static public string getFullName(){
    string full_name = $"{names[rnd.Next(0,names.Count)]} {surnames[rnd.Next(0,surnames.Count)]}";
    Debug.Log(full_name);
    return full_name;
  }
}
