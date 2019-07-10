using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using System.Linq;

public class Club : MonoBehaviour
{
  private List<FootballPlayer> footballPlayers;


  public int power(){
    return footballPlayers.Select( x => x.power()).Sum();
  }
}
