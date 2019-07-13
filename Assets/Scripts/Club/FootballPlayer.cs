using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class FootballPlayer : MonoBehaviour
{
  public int defSkill { get; set; }
  public int midSkill { get; set; }
  public int atkSkill { get; set; }
  public int gkSkill { get; set; }
  public string name { get; set; }

  /*
  Possible three variables that a player could possibly contain:

  private int defAbility;
  private int midAbility;
  private int atkAbility;

  */

  public FootballPlayer(string _name = "Insert Name Here",
                        int _defending = 1,
                        int _attacking = 1,
                        int _midfield = 1,
                        int _goalkeeping = 1){
    defSkill = 10 * _defending;
    atkSkill = 10 * _attacking;
    midSkill = 10 * _midfield;
    gkSkill = 10 * _goalkeeping;
    name = _name;
  }
}
