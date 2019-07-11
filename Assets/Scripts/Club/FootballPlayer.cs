﻿using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class FootballPlayer : MonoBehaviour
{
  public int ability { get; set; }
  public string name { get; set; }

  /*
  Possible three variables that a player could possibly contain:

  private int defAbility;
  private int midAbility;
  private int atkAbility;

  */

  public FootballPlayer(string _name = "Some Name", int _powerMultiplier = 1){
    ability = 10 * _powerMultiplier;
    name = _name;
  }
}
