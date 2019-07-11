using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class FootballPlayer : MonoBehaviour
{
  private int ability;
  private string name;

  public FootballPlayer(string _name, int _ability){
    ability = _ability;
    name = _name;
  }

  public int power(){
    return ability;
  }
}
