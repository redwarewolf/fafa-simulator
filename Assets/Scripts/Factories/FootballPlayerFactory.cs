using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class FootballPlayerFactory : MonoBehaviour
{

  public FootballPlayerFactory(){

  }

  public FootballPlayer newFootballPlayer(string _name = "Pepito Perinola", int _powerMultiplier = 1){
    return new FootballPlayer(_name, _powerMultiplier);
  }

  public List<FootballPlayer> multipleNewFootballPlayers(int ammount = 1, int _powerMultiplier = 1){
    List<FootballPlayer> players = new List<FootballPlayer>();
    for(int i = 0; i < ammount; i++){
      players.Add(newFootballPlayer("A Name", _powerMultiplier));
    }
    return players;
  }
}
