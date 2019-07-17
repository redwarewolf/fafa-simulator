using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class FootballPlayerFactory : MonoBehaviour
{

  public FootballPlayerFactory(){

  }

  static public FootballPlayer newFootballPlayer(string _name = "Pepito Perinola",
                                                 int _defending = 1,
                                                 int _attacking = 1,
                                                 int _midfield = 1,
                                                 int _goalkeeping = 1){
    return new FootballPlayer(_name, _defending, _attacking, _midfield, _goalkeeping);
  }

  static public List<FootballPlayer> multipleNewFootballPlayers(int ammount = 1, int _powerMultiplier = 1){
    List<FootballPlayer> players = new List<FootballPlayer>();
    for(int i = 0; i < ammount; i++){
      players.Add(newFootballPlayer(NameGenerator.getFullName(), _powerMultiplier));
    }
    return players;
  }
}
